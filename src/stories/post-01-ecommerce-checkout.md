# Reliable E-commerce Checkout with Tasker

*How workflow orchestration turns a fragile checkout pipeline into a resilient, observable process.*

> **Handler examples** use Python DSL syntax. See [Class-Based Handlers](../reference/class-based-handlers.md) for the class-based alternative. Full implementations in all four languages are linked at the bottom.

## The Problem

Your checkout flow works — most of the time. A customer adds items to their cart, enters payment details, and clicks "Place Order." Behind the scenes, your application validates the cart, charges the payment gateway, reserves inventory, creates the order record, and fires off a confirmation email. Five steps, all wired together in a single controller action.

Then a payment gateway times out mid-checkout. Your code has already validated the cart but hasn't reserved inventory yet. The customer sees an error, retries, and now you have a double charge to sort out. Your on-call engineer spends the evening tracing logs across services trying to figure out which step failed and whether the customer was actually charged.

This is the reliability problem that workflow orchestration solves. Instead of wiring steps together in application code, you declare them as a workflow template and let the orchestrator handle sequencing, retries, and error classification.

## The Fragile Approach

Most checkout implementations start as a procedural chain in a controller:

```python
def process_order(cart, payment, customer):
    validated = validate_cart(cart)
    charge = process_payment(payment, validated.total)
    inventory = reserve_inventory(validated.items)
    order = create_order(customer, validated, charge, inventory)
    send_confirmation(customer.email, order)
    return order
```

Every step assumes the previous one succeeded. There's no retry logic, no distinction between "the payment gateway is temporarily down" (retry) and "the card was declined" (don't retry), and no way to resume from the middle if something fails partway through.

## The Tasker Approach

With Tasker, you break the checkout into a **task template** that defines steps and their dependencies, and **step handlers** that implement the business logic. The orchestrator takes care of sequencing, retry with backoff, and error classification.

### Task Template (YAML)

The workflow definition lives in a YAML file. Each step declares which handler runs it, what it depends on, and how retries should work:

```yaml
name: ecommerce_order_processing
namespace_name: ecommerce
version: 1.0.0
description: "Complete e-commerce order processing: validate -> payment -> inventory -> order -> confirmation"

steps:
  - name: validate_cart
    description: "Validate cart items, check availability, calculate totals"
    handler:
      callable: Ecommerce::StepHandlers::ValidateCartHandler
    dependencies: []
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100

  - name: process_payment
    description: "Process customer payment using payment service"
    handler:
      callable: Ecommerce::StepHandlers::ProcessPaymentHandler
    dependencies:
      - validate_cart
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100

  - name: update_inventory
    description: "Reserve inventory for order items"
    handler:
      callable: Ecommerce::StepHandlers::UpdateInventoryHandler
    dependencies:
      - process_payment
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential

  - name: create_order
    description: "Create order record with customer, payment, and inventory details"
    handler:
      callable: Ecommerce::StepHandlers::CreateOrderHandler
    dependencies:
      - update_inventory
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential

  - name: send_confirmation
    description: "Send order confirmation email to customer"
    handler:
      callable: Ecommerce::StepHandlers::SendConfirmationHandler
    dependencies:
      - create_order
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
```

The `dependencies` field creates a linear pipeline: `validate_cart` -> `process_payment` -> `update_inventory` -> `create_order` -> `send_confirmation`. Tasker executes them in order, passing each step's results to its dependents.

> **Full template**: [ecommerce\_order\_processing.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/ecommerce_order_processing.yaml)

### Step Handlers

Each handler is a thin DSL wrapper: it declares a typed input model, then delegates to a service function. The orchestrator handles sequencing, retries, and error classification.

#### ValidateCartHandler — Input Validation and Pricing

**Type definition** (the contract):

```python
# app/services/types.py
class EcommerceOrderInput(BaseModel):
    cart_items: list[dict[str, Any]] | None = None
    customer_email: str | None = None
    payment_token: str | None = None
```

**Handler** (DSL declaration + service delegation):

```python
# app/handlers/ecommerce.py
from tasker_core.step_handler.functional import step_handler, inputs
from app.services.types import EcommerceOrderInput
from app.services import ecommerce as svc

@step_handler("ecommerce_validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context):
    return svc.validate_cart_items(
        cart_items=inputs.cart_items,
        customer_email=inputs.customer_email,
    )
```

The `@inputs` decorator extracts fields from the task's submitted context and validates them against the Pydantic model. Invalid data raises a **permanent error** — there's no point retrying a request with an empty cart. The service function (`svc.validate_cart_items`) contains the business logic: price calculations, tax, shipping thresholds.

> **Full implementations**: [FastAPI](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/ecommerce.py) | [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/ecommerce/) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/ecommerce.ts)

#### ProcessPaymentHandler — Dependency Access and Error Classification

The payment handler demonstrates two critical patterns: reading results from an upstream step via `@depends_on`, and classifying errors so the orchestrator knows whether to retry.

```python
from tasker_core.step_handler.functional import step_handler, depends_on, inputs
from tasker_core import PermanentError, RetryableError
from app.services.types import EcommerceOrderInput, EcommerceValidateCartResult
from app.services import ecommerce as svc

@step_handler("ecommerce_process_payment")
@depends_on(cart_result=("validate_cart", EcommerceValidateCartResult))
@inputs(EcommerceOrderInput)
def process_payment(
    cart_result: EcommerceValidateCartResult,
    inputs: EcommerceOrderInput,
    context,
):
    return svc.process_payment(
        cart_result=cart_result,
        payment_token=inputs.payment_token,
    )
```

The `@depends_on` decorator declares that this handler needs the result from `validate_cart`, typed as `EcommerceValidateCartResult`. The orchestrator injects the validated, typed result directly into the function signature — no manual parsing or `get_dependency_result()` calls.

The service function classifies errors:

- **PermanentError** (declined card, invalid data): The orchestrator marks the step as failed and stops. No retry will fix a declined card.
- **RetryableError** (gateway timeout, network blip): The orchestrator retries with exponential backoff up to `max_attempts`.

> **Full implementations**: [FastAPI](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/ecommerce.py) | [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/ecommerce/) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/ecommerce.ts)

### Creating a Task

Your application code submits work to Tasker by creating a task. The orchestrator picks it up and runs the step handlers in dependency order.

**Ruby (Rails Controller)**

```ruby
class OrdersController < ApplicationController
  def create
    order = Order.create!(
      customer_email: order_params[:customer_email],
      items: order_params[:cart_items],
      status: 'pending'
    )

    task = TaskerCore::Client.create_task(
      name:      'ecommerce_order_processing',
      namespace: 'ecommerce',
      context:   {
        customer_email:  order_params[:customer_email],
        cart_items:      order_params[:cart_items],
        payment_token:   order_params[:payment_token],
        shipping_address: order_params[:shipping_address],
        domain_record_id: order.id
      }
    )

    order.update!(task_uuid: task['id'], status: 'processing')
    render json: { id: order.id, status: 'processing', task_uuid: order.task_uuid }, status: :created
  end
end
```

**TypeScript (Bun/Hono Route)**

```typescript
ordersRoute.post('/', async (c) => {
  const { customer_email, items, payment_info } = await c.req.json();

  const [order] = await db.insert(orders).values({
    customerEmail: customer_email, items, status: 'pending',
  }).returning();

  const ffiLayer = new FfiLayer();
  await ffiLayer.load();
  const client = new TaskerClient(ffiLayer);

  const task = client.createTask({
    name: 'ecommerce_order_processing',
    context: { order_id: order.id, customer_email, cart_items: items, payment_info },
    initiator: 'bun-app',
    reason: `Process order #${order.id}`,
    idempotencyKey: `order-${order.id}`,
  });

  await db.update(orders).set({ taskUuid: task.task_uuid, status: 'processing' })
    .where(eq(orders.id, order.id));

  return c.json({ id: order.id, status: 'processing', task_uuid: task.task_uuid }, 201);
});
```

Both implementations follow the same pattern: create a domain record, submit the workflow to Tasker with the relevant context, and store the task UUID for status tracking.

> **Full implementations**: [Rails controller](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/controllers/orders_controller.rb) | [Bun/Hono route](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/routes/orders.ts)

## Key Concepts

- **Linear dependencies**: Each step declares what it depends on. The orchestrator guarantees execution order without you writing sequencing logic.
- **Typed inputs via DSL**: `@inputs` extracts fields from the task context into a validated Pydantic model. `@depends_on` injects upstream step results as typed parameters. No manual parsing needed.
- **Permanent vs. retryable errors**: Handlers classify failures so the orchestrator can retry transient issues (gateway timeouts) while immediately failing on business errors (declined cards).
- **Task creation via FFI client**: Your application submits work through a client that communicates with the Rust orchestration core. The same workflow template runs regardless of which language your handlers are written in.

## Full Implementations

The complete e-commerce checkout workflow is implemented in all four supported languages:

| Language | Handlers | Template | Route/Controller |
|----------|----------|----------|------------------|
| Ruby (Rails) | [handlers/ecommerce/](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/ecommerce/) | [ecommerce\_order\_processing.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/ecommerce_order_processing.yaml) | [orders\_controller.rb](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/controllers/orders_controller.rb) |
| TypeScript (Bun/Hono) | [handlers/ecommerce.ts](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/ecommerce.ts) | [ecommerce\_order\_processing.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/config/tasker/templates/ecommerce_order_processing.yaml) | [routes/orders.ts](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/routes/orders.ts) |
| Python (FastAPI) | [handlers/ecommerce.py](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/ecommerce.py) | [ecommerce\_order\_processing.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/config/tasker/templates/ecommerce_order_processing.yaml) | [routers/orders.py](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/routers/orders.py) |
| Rust (Axum) | [handlers/ecommerce.rs](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/src/handlers/ecommerce.rs) | [ecommerce\_order\_processing.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/config/tasker/templates/ecommerce_order_processing.yaml) | [routes/orders.rs](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/src/routes/orders.rs) |

## What's Next

A linear pipeline works well for checkout, but real systems have steps that can run in parallel. In [Post 02: Data Pipeline Resilience](post-02-data-pipeline.md), we'll build an analytics ETL workflow where three data sources are extracted concurrently, transformed independently, and then aggregated — demonstrating Tasker's DAG execution engine and how parallel steps dramatically reduce pipeline runtime.

---

*See this pattern implemented in all four frameworks on the [Example Apps](../getting-started/example-apps.md) page.*
