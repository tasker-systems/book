# Core Concepts

This page explains the fundamental building blocks of Tasker.

## Tasks

A **Task** is a unit of work submitted to Tasker for execution. Tasks have:

- A **task template** that defines the workflow structure
- An **initiator** identifying the source (e.g., `user:123`, `system:scheduler`)
- A **context** containing input data and metadata
- A **state** managed by a 12-state machine (see below)

```json
{
  "name": "order_fulfillment",
  "initiator": "api:checkout",
  "context": {
    "order_id": "ORD-12345",
    "customer_email": "customer@example.com"
  }
}
```

## Task Templates

A **Task Template** is a YAML definition of a workflow. It specifies:

- **Steps** to execute
- **Dependencies** between steps (creating a DAG)
- **Handler mappings** connecting steps to your code

```yaml
name: order_fulfillment
namespace_name: ecommerce
version: 1.0.0
steps:
  - name: validate_order
    handler:
      callable: OrderValidationHandler
    dependencies: []

  - name: reserve_inventory
    handler:
      callable: InventoryHandler
    dependencies:
      - validate_order

  - name: charge_payment
    handler:
      callable: PaymentHandler
    dependencies:
      - validate_order
```

## Steps

A **Step** is a single operation within a workflow. Steps:

- Execute independently once dependencies are satisfied
- Can run in parallel when they have no mutual dependencies
- Return results that downstream steps can access
- Can be retried on failure

### Task Lifecycle

Tasks progress through a multi-phase lifecycle managed by the orchestration actors:

```
Pending → Initializing → EnqueuingSteps → StepsInProcess → EvaluatingResults → Complete
```

The evaluating phase may loop back to enqueue more steps as dependencies are satisfied, wait for retries, or transition to terminal states (`Complete`, `Error`, `Cancelled`, `ResolvedManually`). Tasks support cancellation from any non-terminal state and manual resolution from `BlockedByFailures`.

### Step Lifecycle

Steps follow a worker-to-orchestration handoff pattern through 10 states:

```
Pending → Enqueued → InProgress → EnqueuedForOrchestration → Complete
```

After a worker executes a step, the result is enqueued back to orchestration for processing. Steps can also transition through `WaitingForRetry` for automatic retry with backoff, or be cancelled, failed, or manually resolved.

For the full state machine diagrams and transition tables, see [States and Lifecycles](../architecture/states-and-lifecycles.md).

## Step Handlers

A **Step Handler** is your code that executes a step's business logic. The DSL approach declares what a handler receives — its inputs from the task context and results from upstream steps — and delegates to a service:

```python
from tasker_core.step_handler.functional import inputs, step_handler
from app.services.types import EcommerceOrderInput
from app.services import ecommerce as svc

@step_handler("validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context: StepContext):
    return svc.validate_cart_items(inputs.resolved_items)
```

The `@inputs` decorator extracts fields from the task context into a typed Pydantic model. The `@depends_on` decorator (shown below) does the same for upstream step results. Your handler function receives typed arguments instead of parsing raw JSON.

> Class-based handlers (`class MyHandler(StepHandler)`) are also supported. See [Class-Based Handlers](../reference/class-based-handlers.md).

## Dependency Results

Steps can access typed results from their dependencies using `@depends_on`:

```python
from tasker_core.step_handler.functional import depends_on, inputs, step_handler
from app.services.types import EcommerceOrderInput, EcommerceValidateCartResult

@step_handler("process_payment")
@depends_on(cart_result=("validate_cart", EcommerceValidateCartResult))
@inputs(EcommerceOrderInput)
def process_payment(
    cart_result: EcommerceValidateCartResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.process_payment(
        payment_token=inputs.payment_token,
        total=cart_result.total or 0.0,
    )
```

Each `@depends_on` entry maps a parameter name to a `("step_name", ResultModel)` tuple. Tasker resolves the upstream step's result and deserializes it into the model, so your handler receives a typed object — not a raw dict.

## Workflow Steps

A **Workflow Step** is a special step that starts another task as a sub-workflow:

```yaml
steps:
  - name: process_line_items
    handler:
      callable: WorkflowHandler
      initialization:
        task_template: line_item_processing
```

This enables composing complex workflows from simpler building blocks.

## Error Handling

Tasker distinguishes between error types:

| Error Type | Behavior |
|------------|----------|
| `PermanentError` | No retry; step fails immediately |
| `RetryableError` | Automatically retried with backoff |

```python
from tasker_core.errors import PermanentError, RetryableError

def call(self, context):
    if invalid_input:
        raise PermanentError(message="Invalid order ID format", error_code="INVALID_ID")
    if service_unavailable:
        raise RetryableError(message="Payment gateway timeout", error_code="GATEWAY_TIMEOUT")
```

## Next Steps

- [Handler Types](handler-types.md) — The four handler types and when to use each
- [Your First Handler](../building/first-handler.md) — Write your first step handler
- [Your First Workflow](../building/first-workflow.md) — Create a complete workflow
