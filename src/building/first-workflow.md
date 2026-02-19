# Your First Workflow

This guide walks you through creating a complete workflow with multiple steps. We'll use the e-commerce order processing pattern from the [example apps](../getting-started/example-apps.md), adapting it to demonstrate parallel execution.

## What is a Workflow?

A **Workflow** is a directed acyclic graph (DAG) of steps defined in a **task template** YAML file. Steps execute when their dependencies are satisfied, enabling parallel execution where possible.

## Example: Order Processing

Let's build an order processing workflow with five steps. After validating the cart, payment processing and inventory reservation happen **in parallel** — they're independent operations that don't need each other's results. Once both succeed, we create the order record and send the confirmation:

```text
           ┌──────────────┐
           │ validate_cart │
           └──────┬───────┘
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
┌──────────────┐   ┌──────────────┐
│   process    │   │   update     │
│   payment    │   │  inventory   │
└──────┬───────┘   └──────┬───────┘
        │                  │
        └────────┬─────────┘
                 ▼
        ┌──────────────┐
        │ create_order │
        └──────┬───────┘
               │
               ▼
        ┌──────────────┐
        │    send      │
        │ confirmation │
        └──────────────┘
```

This is a real-world pattern: payment authorization and inventory reservation are calls to different external systems. Running them in parallel reduces total checkout time. The order record isn't created until both succeed, and the confirmation email isn't sent until the order exists.

## Step 1: Define the Task Template

Create a YAML file defining the workflow structure. You can generate a starter template with `tasker-ctl`:

```bash
tasker-ctl template generate task_template \
  --language python \
  --param name=EcommerceOrderProcessing \
  --param namespace=ecommerce \
  --param handler_callable=handlers.ecommerce.ValidateCartHandler
```

Then extend the generated single-step template into the full DAG:

```yaml
# config/tasker/templates/ecommerce_order_processing.yaml
name: ecommerce_order_processing
namespace_name: ecommerce
version: "1.0.0"
description: "E-commerce checkout: validate → (payment ‖ inventory) → order → confirm"

steps:
  - name: validate_cart
    description: "Validate cart items, check availability, calculate totals"
    handler:
      callable: handlers.ecommerce.ValidateCartHandler
      initialization: {}
    dependencies: []
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: process_payment
    description: "Authorize payment through payment gateway"
    handler:
      callable: handlers.ecommerce.ProcessPaymentHandler
      initialization: {}
    dependencies:
      - validate_cart
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: update_inventory
    description: "Reserve inventory for order items"
    handler:
      callable: handlers.ecommerce.UpdateInventoryHandler
      initialization: {}
    dependencies:
      - validate_cart
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: create_order
    description: "Create order record from payment and inventory results"
    handler:
      callable: handlers.ecommerce.CreateOrderHandler
      initialization: {}
    dependencies:
      - process_payment
      - update_inventory
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: send_confirmation
    description: "Send order confirmation email to customer"
    handler:
      callable: handlers.ecommerce.SendConfirmationHandler
      initialization: {}
    dependencies:
      - create_order
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

input_schema:
  type: object
  required:
    - cart_items
    - customer_email
  properties:
    cart_items:
      type: array
      items:
        type: object
        required: [sku, name, quantity, unit_price]
        properties:
          sku:
            type: string
          name:
            type: string
          quantity:
            type: integer
          unit_price:
            type: number
    customer_email:
      type: string
      format: email
    payment_token:
      type: string
```

### Key YAML Fields

| Field | Description |
|-------|-------------|
| `name` | Task template name (used in API submissions) |
| `namespace_name` | Logical grouping for templates and queues (max 29 chars) |
| `steps` | List of steps forming the execution DAG |
| `handler.callable` | Identifies which handler class processes this step |
| `handler.initialization` | Configuration passed to the handler at setup |
| `dependencies` | List of step names that must complete before this step runs |
| `retry` | Retry policy (retryable, attempts, backoff strategy, timing) |
| `input_schema` | Optional JSON Schema for validating task context |

### How Dependencies Create the DAG

The `dependencies` field defines the execution graph:

- `validate_cart` has no dependencies — it runs first
- `process_payment` and `update_inventory` both depend only on `validate_cart` — they run **in parallel** once validation completes
- `create_order` depends on both `process_payment` and `update_inventory` — it waits for **both** to complete (convergence point)
- `send_confirmation` depends on `create_order` — it runs last

Tasker resolves these dependencies automatically. You declare *what* depends on *what*, and the engine figures out what can run in parallel.

## Step 2: Implement Handlers

Each step needs a handler. The following Python implementations are adapted from the [FastAPI example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app) — they show the patterns you'll use in real handlers.

### Validate Cart

The entry-point handler reads from the task context and validates the input:

```python
from tasker_core import ErrorType, StepContext, StepHandler, StepHandlerResult


class ValidateCartHandler(StepHandler):
    handler_name = "validate_cart"
    handler_version = "1.0.0"

    TAX_RATE = 0.08
    FREE_SHIPPING_THRESHOLD = 100.00
    STANDARD_SHIPPING = 9.99

    def call(self, context: StepContext) -> StepHandlerResult:
        cart_items = context.get_input("cart_items")
        if not cart_items:
            return StepHandlerResult.failure(
                message="Cart is empty or items field is missing",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="EMPTY_CART",
            )

        validated_items = []
        subtotal = 0.0

        for idx, item in enumerate(cart_items):
            sku = item.get("sku")
            quantity = item.get("quantity", 0)
            unit_price = item.get("unit_price", 0.0)

            if not sku or quantity < 1 or unit_price <= 0:
                return StepHandlerResult.failure(
                    message=f"Invalid item at index {idx}",
                    error_type=ErrorType.VALIDATION_ERROR,
                    retryable=False,
                    error_code="INVALID_ITEM",
                )

            line_total = round(quantity * unit_price, 2)
            subtotal += line_total
            validated_items.append({
                "sku": sku,
                "name": item.get("name", sku),
                "quantity": quantity,
                "unit_price": unit_price,
                "line_total": line_total,
            })

        subtotal = round(subtotal, 2)
        tax = round(subtotal * self.TAX_RATE, 2)
        shipping = 0.0 if subtotal >= self.FREE_SHIPPING_THRESHOLD else self.STANDARD_SHIPPING
        total = round(subtotal + tax + shipping, 2)

        return StepHandlerResult.success(result={
            "validated_items": validated_items,
            "item_count": len(validated_items),
            "subtotal": subtotal,
            "tax": tax,
            "shipping": shipping,
            "total": total,
        })
```

Key points:

- `context.get_input("cart_items")` reads from the task context (the data submitted when the task was created)
- Validation failures return `StepHandlerResult.failure(...)` with `retryable=False` — bad data won't get better on retry
- The result dict is available to downstream steps via `get_dependency_result("validate_cart")`

### Process Payment (runs in parallel with Update Inventory)

This handler reads from both the task context and an upstream dependency:

```python
class ProcessPaymentHandler(StepHandler):
    handler_name = "process_payment"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        payment_token = context.get_input("payment_token") or "tok_test_success"

        # Read the total from the validate_cart step's result
        cart_result = context.get_dependency_result("validate_cart")
        if cart_result is None:
            return StepHandlerResult.failure(
                message="Missing validate_cart dependency result",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        total = cart_result.get("total", 0.0)

        # Call payment gateway (simulated here)
        if payment_token == "tok_test_declined":
            return StepHandlerResult.failure(
                message="Payment declined",
                error_type=ErrorType.PERMANENT_ERROR,
                retryable=False,
                error_code="PAYMENT_DECLINED",
            )

        if payment_token == "tok_test_gateway_error":
            return StepHandlerResult.failure(
                message="Payment gateway error, will retry",
                error_type=ErrorType.RETRYABLE_ERROR,
                retryable=True,
                error_code="GATEWAY_ERROR",
            )

        return StepHandlerResult.success(result={
            "payment_id": "pay_abc123",
            "transaction_id": "txn_def456",
            "amount_charged": total,
            "status": "completed",
        })
```

Key points:

- `context.get_dependency_result("validate_cart")` retrieves the result dict from an upstream step
- Gateway timeouts use `retryable=True` — Tasker automatically retries with exponential backoff
- Declined payments use `retryable=False` — a permanent failure that stops the workflow

### Update Inventory (runs in parallel with Process Payment)

```python
class UpdateInventoryHandler(StepHandler):
    handler_name = "update_inventory"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        cart_result = context.get_dependency_result("validate_cart")
        if cart_result is None:
            return StepHandlerResult.failure(
                message="Missing validate_cart dependency result",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        validated_items = cart_result.get("validated_items", [])
        reservations = []

        for item in validated_items:
            reservations.append({
                "sku": item["sku"],
                "quantity_reserved": item["quantity"],
                "reservation_id": f"res_{item['sku'].lower()}",
                "warehouse": "WH-EAST-01",
            })

        return StepHandlerResult.success(result={
            "reservations": reservations,
            "total_items_reserved": sum(r["quantity_reserved"] for r in reservations),
            "inventory_log_id": "log_inv_001",
        })
```

### Create Order (convergence point)

This handler depends on **both** `process_payment` and `update_inventory`. It only runs after both parallel branches complete successfully:

```python
class CreateOrderHandler(StepHandler):
    handler_name = "create_order"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        customer_email = context.get_input("customer_email")

        # Gather results from all upstream steps
        cart_result = context.get_dependency_result("validate_cart")
        payment_result = context.get_dependency_result("process_payment")
        inventory_result = context.get_dependency_result("update_inventory")

        if not all([cart_result, payment_result, inventory_result]):
            return StepHandlerResult.failure(
                message="Missing upstream dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        return StepHandlerResult.success(result={
            "order_id": "ORD-20260218-ABC",
            "customer_email": customer_email,
            "items": cart_result["validated_items"],
            "total": cart_result["total"],
            "payment_id": payment_result["payment_id"],
            "transaction_id": payment_result["transaction_id"],
            "inventory_log_id": inventory_result["inventory_log_id"],
            "status": "confirmed",
        })
```

Key points:

- `get_dependency_result()` can access results from **any** completed upstream step, not just direct parents
- This handler reads from three different upstream steps — the DAG ensures all have completed
- If either parallel branch fails (payment declined, inventory unavailable), this step never runs

### Send Confirmation

```python
class SendConfirmationHandler(StepHandler):
    handler_name = "send_confirmation"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        order_result = context.get_dependency_result("create_order")
        if order_result is None:
            return StepHandlerResult.failure(
                message="Missing create_order dependency result",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        return StepHandlerResult.success(result={
            "email_sent": True,
            "recipient": order_result["customer_email"],
            "subject": f"Order Confirmation - {order_result['order_id']}",
            "status": "sent",
        })
```

## Step 3: Submit a Task

Submit a task via the REST API:

```bash
curl -X POST http://localhost:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ecommerce_order_processing",
    "namespace": "ecommerce",
    "version": "1.0.0",
    "initiator": "api:checkout",
    "source_system": "web",
    "reason": "New order received",
    "context": {
      "customer_email": "customer@example.com",
      "payment_token": "tok_test_success",
      "cart_items": [
        {"sku": "WIDGET-A", "name": "Widget A", "quantity": 2, "unit_price": 29.99},
        {"sku": "GADGET-B", "name": "Gadget B", "quantity": 1, "unit_price": 49.99}
      ]
    }
  }'
```

Or with `tasker-ctl`:

```bash
tasker-ctl task create \
  --name ecommerce_order_processing \
  --namespace ecommerce \
  --input '{"customer_email": "customer@example.com", "cart_items": [{"sku": "WIDGET-A", "name": "Widget A", "quantity": 2, "unit_price": 29.99}]}'
```

## Execution Flow

When this task runs:

1. **validate_cart** executes first (no dependencies)
2. **process_payment** and **update_inventory** execute in parallel (both depend only on validate_cart)
3. **create_order** executes after **both** parallel steps complete (convergence)
4. **send_confirmation** executes after create_order completes

The total execution time is determined by the longest path through the DAG, not the sum of all steps. If payment takes 2 seconds and inventory takes 1 second, step 3 begins at the 2-second mark — the inventory result is already waiting.

## See It in Action

The [example apps](../getting-started/example-apps.md) implement this e-commerce workflow (and three others) in all four languages — Rails, FastAPI, Bun, and Axum. Each app is a fully working project you can clone and run with Docker Compose.

The example apps also include more complex DAG patterns:

- **Data Pipeline** — Three parallel extract branches, each feeding its own transform, converging at aggregation (8 steps)
- **Microservices** — User registration with parallel billing and preferences setup (5 steps, diamond pattern)
- **Cross-Namespace** — Customer success workflow that delegates to a payments namespace (namespace isolation)

## Next Steps

- Language guides: [Ruby](ruby.md) | [Python](python.md) | [TypeScript](typescript.md) | [Rust](rust.md)
- [Architecture Overview](../architecture/README.md) — Understand lifecycle actors and DAG execution
- [Handler Types](../getting-started/handler-types.md) — API, Decision, and Batchable handler patterns
