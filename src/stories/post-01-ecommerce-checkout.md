# Reliable E-commerce Checkout with Tasker

*How workflow orchestration turns a fragile checkout pipeline into a resilient, observable process.*

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

Each step handler receives a **context** object that provides access to the task's input data and the results of upstream steps. Handlers return a success result or raise typed errors that tell the orchestrator whether to retry.

#### ValidateCartHandler — Input Validation and Pricing

**Ruby (Rails)**

```ruby
class ValidateCartHandler < TaskerCore::StepHandler::Base
  TAX_RATE = 0.08
  SHIPPING_THRESHOLD = 75.00
  SHIPPING_COST = 9.99

  def call(context)
    cart_items = context.get_input('cart_items')
    customer_email = context.get_input('customer_email')

    raise TaskerCore::Errors::PermanentError.new(
      'Cart is empty', error_code: 'EMPTY_CART'
    ) if cart_items.nil? || cart_items.empty?

    validated_items = []
    subtotal = 0.0

    cart_items.each do |item|
      quantity = item['quantity'].to_i
      price    = item['unit_price'].to_f

      raise TaskerCore::Errors::PermanentError.new(
        "Invalid quantity for #{item['sku']}: #{quantity}",
        error_code: 'INVALID_QUANTITY'
      ) if quantity < 1 || quantity > 100

      line_total = (quantity * price).round(2)
      subtotal += line_total
      validated_items << { sku: item['sku'], quantity: quantity,
                           unit_price: price, line_total: line_total }
    end

    tax = (subtotal * TAX_RATE).round(2)
    shipping = subtotal >= SHIPPING_THRESHOLD ? 0.0 : SHIPPING_COST
    total = (subtotal + tax + shipping).round(2)

    TaskerCore::Types::StepHandlerCallResult.success(
      result: { validated_items: validated_items, subtotal: subtotal,
                tax: tax, shipping: shipping, total: total }
    )
  end
end
```

**TypeScript (Bun/Hono)**

```typescript
export class ValidateCartHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.ValidateCartHandler';

  async call(context: StepContext): Promise<StepHandlerResult> {
    const cartItems = context.getInput<CartItem[]>('cart_items');

    if (!cartItems || cartItems.length === 0) {
      return this.failure('Cart is empty or missing', ErrorType.VALIDATION_ERROR, false);
    }

    const validatedItems: CartItem[] = [];
    for (const item of cartItems) {
      if (item.price <= 0 || !Number.isInteger(item.quantity) || item.quantity <= 0) {
        continue; // skip invalid items
      }
      validatedItems.push(item);
    }

    const subtotal = validatedItems.reduce(
      (sum, item) => sum + item.price * item.quantity, 0
    );
    const tax = Math.round(subtotal * 0.0875 * 100) / 100;
    const shipping = subtotal >= 75.0 ? 0 : 9.99;
    const total = Math.round((subtotal + tax + shipping) * 100) / 100;

    return this.success({
      validated_items: validatedItems,
      subtotal, tax, shipping, total,
      free_shipping: subtotal >= 75.0,
    });
  }
}
```

Both implementations use `context.getInput()` (Ruby: `get_input`) to read from the task's initial input. Invalid data raises a **permanent error** — there's no point retrying a request with an empty cart.

> **Full implementations**: [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/ecommerce/validate_cart_handler.rb) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/ecommerce.ts)

#### ProcessPaymentHandler — Dependency Access and Error Classification

The payment handler demonstrates two critical patterns: reading results from an upstream step, and classifying errors so the orchestrator knows whether to retry.

**Ruby (Rails)**

```ruby
class ProcessPaymentHandler < TaskerCore::StepHandler::Base
  DECLINED_TOKENS = %w[tok_test_declined tok_insufficient_funds tok_expired].freeze
  GATEWAY_ERROR_TOKENS = %w[tok_gateway_error tok_timeout].freeze

  def call(context)
    payment_info = context.get_input('payment_info')
    total = context.get_dependency_field('validate_cart', 'total')

    raise TaskerCore::Errors::PermanentError.new(
      'Payment token is required', error_code: 'MISSING_TOKEN'
    ) if payment_info[:token].blank?

    if DECLINED_TOKENS.include?(payment_info[:token])
      raise TaskerCore::Errors::PermanentError.new(
        'Payment declined', error_code: 'PAYMENT_DECLINED'
      )
    end

    if GATEWAY_ERROR_TOKENS.include?(payment_info[:token])
      raise TaskerCore::Errors::RetryableError.new(
        'Payment gateway temporarily unavailable'
      )
    end

    # Process payment...
    TaskerCore::Types::StepHandlerCallResult.success(
      result: { payment_id: "pay_#{SecureRandom.hex(12)}",
                amount_charged: total, status: 'completed' }
    )
  end
end
```

**TypeScript (Bun/Hono)**

```typescript
export class ProcessPaymentHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.ProcessPaymentHandler';

  async call(context: StepContext): Promise<StepHandlerResult> {
    const paymentInfo = context.getInput<PaymentInfo>('payment_info');
    const cartResult = context.getDependencyResult('validate_cart') as Record<string, unknown>;

    if (!cartResult) {
      return this.failure('Missing cart validation result', ErrorType.HANDLER_ERROR, true);
    }

    const total = cartResult.total as number;

    if (total > 10000) {
      return this.failure(
        'Transaction exceeds single-transaction limit',
        ErrorType.VALIDATION_ERROR, false  // permanent — don't retry
      );
    }

    const transactionId = crypto.randomUUID();
    return this.success({
      payment_id: `pay_${crypto.randomUUID().replace(/-/g, '').substring(0, 12)}`,
      transaction_id: transactionId,
      amount_charged: total,
      status: 'succeeded',
    });
  }
}
```

The key pattern here is **error classification**:

- **PermanentError** (declined card, invalid data): The orchestrator marks the step as failed and stops. No retry will fix a declined card.
- **RetryableError** (gateway timeout, network blip): The orchestrator retries with exponential backoff up to `max_attempts`.

The Ruby handler uses `get_dependency_field('validate_cart', 'total')` to pull a specific field from the upstream step's result. The TypeScript version uses `getDependencyResult('validate_cart')` to get the full result object. Both patterns are part of the cross-language standard API (TAS-137).

> **Full implementations**: [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/ecommerce/process_payment_handler.rb) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/ecommerce.ts)

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
- **`getInput()` / `getDependencyResult()`**: A cross-language API for accessing task inputs and upstream step results. Available in Ruby, TypeScript, Python, and Rust.
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
