# Team Scaling with Namespaces

*How namespace isolation lets multiple teams own workflows with the same name without stepping on each other.*

## The Problem

Your company has grown. The Customer Success team handles refund requests through a multi-step approval workflow. The Payments team processes refunds directly through the payment gateway. Both teams call their workflow `process_refund` — because that's what it does.

Without namespace isolation, you have a naming collision. One team renames their workflow to `cs_process_refund` or `payments_process_refund`, which leads to inconsistent naming conventions, confusion about ownership, and a growing pile of team-prefixed workflow names that nobody wants to maintain. Worse, when the Customer Success team's approval workflow needs to trigger the Payments team's gateway refund, the coupling between teams becomes explicit and brittle.

This is the team scaling problem. As your organization grows from one team with a few workflows to multiple teams with overlapping domain concepts, you need a way to isolate ownership while still enabling coordination.

## The Fragile Approach

Without namespaces, teams resort to naming conventions:

```
# Customer Success team
workflow: cs_process_refund_v2_with_approval

# Payments team
workflow: payments_direct_refund_v3

# Which one does "process a refund" mean?
# Depends on who you ask.
```

Cross-team coordination requires hard-coded references to the other team's workflow name. When the Payments team renames their workflow, the Customer Success team's code breaks. There's no formal boundary between teams — just convention and hope.

## The Tasker Approach

Tasker solves this with **namespaces**. Each team owns a namespace, and workflow names are scoped to that namespace. Both teams can have a workflow called `process_refund` — the fully qualified names are `customer_success.process_refund` and `payments.process_refund`.

### Two Templates, Same Name, Different Namespaces

#### Customer Success: `process_refund`

The Customer Success team's refund workflow includes approval steps and ticket management:

```yaml
name: process_refund
namespace_name: customer_success
version: 1.0.0
description: "Process customer service refunds with approval workflow"

steps:
  - name: validate_refund_request
    description: "Validate customer refund request details"
    handler:
      callable: CustomerSuccess::StepHandlers::ValidateRefundRequestHandler
    dependencies: []
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential

  - name: check_refund_policy
    description: "Verify request complies with refund policies"
    handler:
      callable: CustomerSuccess::StepHandlers::CheckRefundPolicyHandler
    dependencies:
      - validate_refund_request

  - name: get_manager_approval
    description: "Route to manager for approval if needed"
    handler:
      callable: CustomerSuccess::StepHandlers::GetManagerApprovalHandler
    dependencies:
      - check_refund_policy

  - name: execute_refund_workflow
    description: "Call payments team refund workflow (cross-namespace)"
    handler:
      callable: CustomerSuccess::StepHandlers::ExecuteRefundWorkflowHandler
    dependencies:
      - get_manager_approval
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      initial_delay: 5
      max_delay: 60

  - name: update_ticket_status
    description: "Update customer support ticket"
    handler:
      callable: CustomerSuccess::StepHandlers::UpdateTicketStatusHandler
    dependencies:
      - execute_refund_workflow
```

#### Payments: `process_refund`

The Payments team's refund workflow is direct gateway integration — no approval needed:

```yaml
name: process_refund
namespace_name: payments
version: 1.0.0
description: "Process payment gateway refunds with direct API integration"

steps:
  - name: validate_payment_eligibility
    description: "Check if payment can be refunded via gateway"
    handler:
      callable: team_scaling_payments_validate_eligibility
    dependencies: []
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential

  - name: process_gateway_refund
    description: "Execute refund through payment processor"
    handler:
      callable: team_scaling_payments_process_gateway_refund
    dependencies:
      - validate_payment_eligibility
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      initial_delay: 5
      max_delay: 60

  - name: update_payment_records
    description: "Update internal payment status and history"
    handler:
      callable: team_scaling_payments_update_records
    dependencies:
      - process_gateway_refund

  - name: notify_customer
    description: "Send refund confirmation to customer"
    handler:
      callable: team_scaling_payments_notify_customer
    dependencies:
      - update_payment_records
    retry:
      retryable: true
      max_attempts: 5
      backoff: exponential
```

Both templates use `name: process_refund`. The `namespace_name` field is what makes them distinct. When a task is created, the fully qualified identifier is `namespace.name` — so `customer_success.process_refund` and `payments.process_refund` coexist without conflict.

> **Full templates**: [customer\_success\_process\_refund.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/customer_success_process_refund.yaml) | [payments\_process\_refund.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/payments_process_refund.yaml)

### Step Handlers

The namespace boundary extends to handler implementations — and even to language choice. The Customer Success team uses Ruby (Rails), their existing stack. The Payments team chose Rust (Axum) for their handlers because gateway latency is critical and they need predictable sub-millisecond overhead on every refund validation. Both languages connect to the same Tasker orchestration core via FFI.

#### Customer Success: ValidateRefundRequestHandler (Ruby)

The Customer Success handler validates from the customer's perspective — ticket IDs, refund reasons, order history:

```ruby
module CustomerSuccess
  module StepHandlers
    class ValidateRefundRequestHandler < TaskerCore::StepHandler::Base
      VALID_REASONS = %w[defective not_as_described changed_mind
                         late_delivery duplicate_charge].freeze

      def call(context)
        ticket_id     = context.get_input('ticket_id')
        customer_id   = context.get_input('customer_id')
        refund_amount = context.get_input('refund_amount')
        reason        = context.get_input('refund_reason')

        missing = []
        missing << 'ticket_id' if ticket_id.blank?
        missing << 'customer_id' if customer_id.blank?
        missing << 'refund_amount' if refund_amount.nil?
        missing << 'refund_reason' if reason.blank?

        unless missing.empty?
          raise TaskerCore::Errors::PermanentError.new(
            "Missing required fields: #{missing.join(', ')}",
            error_code: 'MISSING_FIELDS'
          )
        end

        unless VALID_REASONS.include?(reason)
          raise TaskerCore::Errors::PermanentError.new(
            "Invalid reason: #{reason}. Must be one of: #{VALID_REASONS.join(', ')}",
            error_code: 'INVALID_REASON'
          )
        end

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            request_validated: true,
            ticket_id: ticket_id,
            customer_id: customer_id,
            refund_amount: refund_amount.to_f,
            reason: reason,
            namespace: 'customer_success',
            validated_at: Time.current.iso8601
          }
        )
      end
    end
  end
end
```

> **Full implementation**: [Rails customer\_success handlers](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/customer_success/)

#### Payments: ValidatePaymentEligibilityHandler (Rust)

The Payments team needs low-latency gateway validation — checking payment method support, refund windows, and remaining balance with zero GC overhead. Their handlers are plain Rust functions that receive the task context as `serde_json::Value`:

```rust
pub fn validate_payment_eligibility(context: &Value) -> Result<Value, String> {
    let payment_id = context.get("payment_id")
        .and_then(|v| v.as_str())
        .ok_or("Missing payment_id in context")?;

    let refund_amount = context.get("refund_amount")
        .and_then(|v| v.as_f64())
        .ok_or("Missing or invalid refund_amount")?;

    let payment_method = context.get("payment_method")
        .and_then(|v| v.as_str())
        .unwrap_or("credit_card");

    if refund_amount <= 0.0 {
        return Err("Refund amount must be positive".to_string());
    }

    // Check if payment method supports refunds
    let refund_supported = match payment_method {
        "credit_card" | "debit_card" | "bank_transfer" => true,
        "gift_card" => refund_amount <= 500.0,
        "crypto" => false,
        _ => true,
    };

    if !refund_supported {
        return Err(format!(
            "Payment method '{}' does not support automated refunds",
            payment_method
        ));
    }

    let now = chrono::Utc::now().to_rfc3339();

    Ok(json!({
        "payment_validated": true,
        "payment_id": payment_id,
        "refund_amount": refund_amount,
        "payment_method": payment_method,
        "eligibility_status": "eligible",
        "validation_timestamp": now,
        "namespace": "payments"
    }))
}
```

The Rust handler uses pattern matching for payment method validation — a natural fit for the exhaustive checking that payment processing requires. The `Result<Value, String>` return type maps directly to Tasker's success/error model. Errors returned as `Err(...)` become permanent failures; the retry policy in the YAML template controls whether the orchestrator retries.

Notice how both handlers include `namespace` in their result. This makes it unambiguous which team's workflow produced a given result, even when viewing task data across the system. And critically, the Customer Success team's Ruby handlers and the Payments team's Rust handlers participate in the same workflow ecosystem — the orchestrator doesn't care what language a handler is written in.

> **Full implementations**: [Rails customer\_success handlers](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/customer_success/) | [Axum payments handlers](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/src/handlers/payments.rs)

### Cross-Namespace Coordination

The Customer Success workflow's `execute_refund_workflow` step demonstrates cross-namespace coordination. After getting manager approval, it creates a task in the **payments** namespace:

```ruby
# Inside CustomerSuccess::StepHandlers::ExecuteRefundWorkflowHandler
def call(context)
  approval = context.get_dependency_result('get_manager_approval')
  validation = context.get_dependency_result('validate_refund_request')

  # Create a task in the payments namespace
  payment_task = TaskerCore::Client.create_task(
    name:      'process_refund',
    namespace: 'payments',     # <-- cross-namespace call
    context:   {
      payment_id:    validation['payment_id'],
      refund_amount: validation['refund_amount'],
      refund_reason: 'customer_request',
      correlation_id: context.task_id  # link back to CS workflow
    }
  )

  TaskerCore::Types::StepHandlerCallResult.success(
    result: {
      payment_task_id: payment_task['id'],
      status: 'delegated_to_payments',
      correlation_id: context.task_id
    }
  )
end
```

The Customer Success team doesn't need to know how the Payments team processes refunds internally. They just create a task in the `payments` namespace with the required inputs. If the Payments team refactors their workflow (adds steps, changes retry policies), the Customer Success workflow is unaffected.

### Creating Tasks in Each Namespace

**Customer Success refund** (triggered by a support agent):

```ruby
task = TaskerCore::Client.create_task(
  name:      'process_refund',
  namespace: 'customer_success',
  context:   {
    ticket_id:     'TICKET-1234',
    customer_id:   'cust_abc123',
    refund_amount: 49.99,
    refund_reason: 'defective',
    customer_email: 'customer@example.com'
  }
)
```

**Payments refund** (triggered by fraud detection or internal tooling):

```ruby
task = TaskerCore::Client.create_task(
  name:      'process_refund',
  namespace: 'payments',
  context:   {
    payment_id:    'pay_xyz789',
    refund_amount: 49.99,
    refund_reason: 'fraud',
    customer_email: 'customer@example.com'
  }
)
```

Same workflow name, different namespaces, different input schemas, different step sequences. Each team owns their namespace independently.

## Key Concepts

- **Namespace isolation**: Workflow names are scoped to namespaces. `customer_success.process_refund` and `payments.process_refund` are distinct workflows that coexist without conflict.
- **Same name, different implementations**: Both teams use the natural name `process_refund` for their workflow. No team-prefix naming conventions needed.
- **Cross-namespace coordination**: One team's step handler can create tasks in another team's namespace. The boundary is clean — just a namespace and name, plus the required inputs.
- **Team ownership**: Each namespace has clear ownership. The Payments team can refactor their `process_refund` workflow without breaking the Customer Success team, as long as the input schema remains compatible.
- **Polyglot handlers**: Namespace isolation extends to language choice. The Customer Success team writes handlers in Ruby; the Payments team chose Rust for low-latency gateway operations. The orchestration core doesn't care — both connect via the same FFI interface.

## Full Implementations

The namespace isolation pattern is demonstrated across all four supported languages:

| Language | Customer Success Handlers | Payments Handlers | Templates |
|----------|--------------------------|-------------------|-----------|
| Ruby (Rails) | [handlers/customer\_success/](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/customer_success/) | [handlers/payments/](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/payments/) | [customer\_success\_process\_refund.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/customer_success_process_refund.yaml), [payments\_process\_refund.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/payments_process_refund.yaml) |
| TypeScript (Bun/Hono) | [handlers/customer-success.ts](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/customer-success.ts) | [handlers/payments.ts](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/payments.ts) | Same YAML structure |
| Python (FastAPI) | [handlers/customer\_success.py](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/customer_success.py) | [handlers/payments.py](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/payments.py) | Same YAML structure |
| Rust (Axum) | [handlers/customer\_success.rs](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/src/handlers/customer_success.rs) | [handlers/payments.rs](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/src/handlers/payments.rs) | Same YAML structure |

## What's Next

With namespaces, your teams can scale independently. But as your workflow count grows, you need visibility into what's happening across all those namespaces. The next posts in this series will explore observability (OpenTelemetry integration and domain events), batch processing patterns, and production debugging workflows.
