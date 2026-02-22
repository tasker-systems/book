# Your First Workflow

This guide walks you through creating a complete workflow with multiple steps. We'll use the e-commerce order processing pattern from the [example apps](../getting-started/example-apps.md), demonstrating parallel execution and typed dependency injection.

> This walkthrough uses Python. See the [Ruby](ruby.md), [TypeScript](typescript.md), and [Rust](rust.md) guides for language-specific examples.

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
      callable: validate_cart
    dependencies: []
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential

  - name: process_payment
    description: "Authorize payment through payment gateway"
    handler:
      callable: process_payment
    dependencies:
      - validate_cart
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential

  - name: update_inventory
    description: "Reserve inventory for order items"
    handler:
      callable: update_inventory
    dependencies:
      - validate_cart
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential

  - name: create_order
    description: "Create order record from payment and inventory results"
    handler:
      callable: create_order
    dependencies:
      - process_payment
      - update_inventory
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential

  - name: send_confirmation
    description: "Send order confirmation email to customer"
    handler:
      callable: send_confirmation
    dependencies:
      - create_order
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential

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
| `handler.callable` | Identifies which handler processes this step |
| `dependencies` | List of step names that must complete before this step runs |
| `retry` | Retry policy (retryable, attempts, backoff strategy) |
| `input_schema` | Optional JSON Schema for validating task context |

### How Dependencies Create the DAG

The `dependencies` field defines the execution graph:

- `validate_cart` has no dependencies — it runs first
- `process_payment` and `update_inventory` both depend only on `validate_cart` — they run **in parallel** once validation completes
- `create_order` depends on both `process_payment` and `update_inventory` — it waits for **both** to complete (convergence point)
- `send_confirmation` depends on `create_order` — it runs last

Tasker resolves these dependencies automatically. You declare *what* depends on *what*, and the engine figures out what can run in parallel.

### YAML Dependencies vs Handler Dependencies

The YAML `dependencies` field and the handler's `@depends_on` decorator serve **different purposes**:

- **YAML `dependencies`** define the **DAG shape** — which steps must complete before this step *starts*. These are **proximal** (direct predecessors only). `create_order` lists `process_payment` and `update_inventory` because it must wait for both.

- **Handler `@depends_on`** declares which **step results** the handler needs injected as typed parameters. These can reference **any ancestor step** — not just direct predecessors. Tasker makes all ancestor results available in the step context.

In the `create_order` handler below, notice that `@depends_on` references `validate_cart` even though the YAML only lists `process_payment` and `update_inventory` as dependencies. The handler can access `validate_cart`'s result because it's a transitive ancestor — Tasker has already executed it earlier in the DAG.

## Step 2: Define Your Types

Before writing handlers, define the types that describe what flows between steps. These are Pydantic models — the same types the DSL uses to inject inputs and dependency results:

```python
# app/services/types.py
from pydantic import BaseModel
from typing import Any

class EcommerceOrderInput(BaseModel):
    items: list[dict[str, Any]] | None = None        # submitted as "items"
    cart_items: list[dict[str, Any]] | None = None    # or "cart_items"
    customer_email: str | None = None
    payment_token: str | None = None

    @property
    def resolved_items(self) -> list[dict[str, Any]]:
        """Accept either field name from the task context."""
        return self.items or self.cart_items or []

class EcommerceValidateCartResult(BaseModel):
    validated_items: list[dict[str, Any]] | None = None
    item_count: int | None = None
    subtotal: float | None = None
    tax: float | None = None
    total: float | None = None

class EcommerceProcessPaymentResult(BaseModel):
    payment_id: str | None = None
    transaction_id: str | None = None
    amount_charged: float | None = None
    status: str | None = None

class EcommerceUpdateInventoryResult(BaseModel):
    total_items_reserved: int | None = None
    inventory_log_id: str | None = None

class EcommerceCreateOrderResult(BaseModel):
    order_id: str | None = None
    customer_email: str | None = None
    total: float | None = None
    status: str | None = None
```

All fields are optional with `None` defaults. This is intentional — task context may not include every field, and upstream step results may vary. The type system provides structure and IDE autocomplete without brittle required-field failures.

## Step 3: Implement Handlers

With types defined, the handlers are short — each one declares what it receives and delegates to a service function:

```python
# app/handlers/ecommerce.py
from tasker_core.step_handler.functional import depends_on, inputs, step_handler
from tasker_core.types import StepContext
from app.services import ecommerce as svc
from app.services.types import (
    EcommerceCreateOrderResult,
    EcommerceOrderInput,
    EcommerceProcessPaymentResult,
    EcommerceUpdateInventoryResult,
    EcommerceValidateCartResult,
)

@step_handler("validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context: StepContext):
    return svc.validate_cart_items(inputs.resolved_items)

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

@step_handler("update_inventory")
@depends_on(cart_result=("validate_cart", EcommerceValidateCartResult))
def update_inventory(cart_result: EcommerceValidateCartResult, context: StepContext):
    return svc.update_inventory(cart_result.validated_items or [])

@step_handler("create_order")
@depends_on(
    cart_result=("validate_cart", EcommerceValidateCartResult),
    payment_result=("process_payment", EcommerceProcessPaymentResult),
    inventory_result=("update_inventory", EcommerceUpdateInventoryResult),
)
@inputs(EcommerceOrderInput)
def create_order(
    cart_result: EcommerceValidateCartResult,
    payment_result: EcommerceProcessPaymentResult,
    inventory_result: EcommerceUpdateInventoryResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.create_order(
        cart=cart_result, payment=payment_result,
        inventory=inventory_result, customer_email=inputs.customer_email,
    )

@step_handler("send_confirmation")
@depends_on(order_result=("create_order", EcommerceCreateOrderResult))
@inputs(EcommerceOrderInput)
def send_confirmation(
    order_result: EcommerceCreateOrderResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.send_confirmation(
        order=order_result, customer_email=inputs.customer_email,
    )
```

That's the entire handler file — five handlers in about 50 lines. The service functions (`svc.validate_cart_items`, `svc.process_payment`, etc.) contain your actual business logic. Tasker doesn't care what happens inside them — it cares about the handler's typed signature and the result it returns.

### Anatomy of a Handler with Dependencies

Look at `create_order` — the convergence point where three parallel branches meet:

```python
@step_handler("create_order")
@depends_on(
    cart_result=("validate_cart", EcommerceValidateCartResult),       # ① upstream step + type
    payment_result=("process_payment", EcommerceProcessPaymentResult), # ② another upstream step
    inventory_result=("update_inventory", EcommerceUpdateInventoryResult),
)
@inputs(EcommerceOrderInput)                                          # ③ task context
def create_order(
    cart_result: EcommerceValidateCartResult,   # injected as typed Pydantic model
    payment_result: EcommerceProcessPaymentResult,
    inventory_result: EcommerceUpdateInventoryResult,
    inputs: EcommerceOrderInput,                # task context as typed model
    context: StepContext,                       # execution metadata
):
    return svc.create_order(...)               # ④ delegate to service
```

1. Each `@depends_on` entry maps a parameter name to a `("step_name", ResultModel)` tuple
2. Tasker resolves the upstream step's result dict and deserializes it into the Pydantic model
3. `@inputs` does the same for the task context
4. The handler function receives fully typed objects and passes them to the service

## Step 4: Submit a Task

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

## Your Services, Tasker's Orchestration

Notice what the handlers *don't* contain: no tax calculations, no payment gateway logic, no inventory reservation algorithms. That business logic lives in your service layer (`app/services/ecommerce.py`), where it can be tested independently and reused outside of Tasker.

The handlers are thin wrappers that declare their typed signature and delegate. Tasker brings workflow orchestration to your existing codebase — it manages the DAG, sequencing, retries, and error classification. Your services do what they've always done.

## See It in Action

The [example apps](../getting-started/example-apps.md) implement this e-commerce workflow (and three others) in all four languages — Rails, FastAPI, Bun, and Axum. Each app is a fully working project you can clone and run with Docker Compose.

The example apps also include more complex DAG patterns:

- **Data Pipeline** — Three parallel extract branches, each feeding its own transform, converging at aggregation (8 steps)
- **Microservices** — User registration with parallel billing and preferences setup (5 steps, diamond pattern)
- **Cross-Namespace** — Customer success workflow that delegates to a payments namespace (namespace isolation)

## Next Steps

- Language guides: [Ruby](ruby.md) | [Python](python.md) | [TypeScript](typescript.md) | [Rust](rust.md)
- [Architecture Overview](../architecture/index.md) — Understand lifecycle actors and DAG execution
- [Handler Types](../getting-started/handler-types.md) — API, Decision, and Batchable handler patterns
