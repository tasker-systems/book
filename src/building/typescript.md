# Building with TypeScript

This guide covers building Tasker step handlers with TypeScript using the
`@tasker-systems/tasker` package in a Bun application.

## Quick Start

Install the package:

```bash
bun add @tasker-systems/tasker
# Or with npm
npm install @tasker-systems/tasker
```

Generate a step handler with `tasker-ctl`:

```bash
tasker-ctl template generate step_handler \
  --language typescript \
  --param name=ValidateCart
```

This creates a handler class that extends `StepHandler` with the standard async
`call(context)` method.

## Writing a Step Handler

Every TypeScript handler extends `StepHandler` and implements `call`:

```typescript
import {
  StepHandler,
  type StepContext,
  type StepHandlerResult,
  ErrorType,
} from '@tasker-systems/tasker';

export class ValidateCartHandler extends StepHandler {
  static handlerName = 'Ecommerce.StepHandlers.ValidateCartHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      const cartItems = context.getInput<CartItem[]>('cart_items');

      if (!cartItems || cartItems.length === 0) {
        return this.failure(
          'Cart is empty or missing',
          ErrorType.VALIDATION_ERROR,
          false,
        );
      }

      // Validate items, calculate totals...
      const validatedItems: CartItem[] = [];
      for (const item of cartItems) {
        if (item.price <= 0 || item.quantity <= 0) {
          return this.failure(
            `Invalid item: ${item.sku}`,
            ErrorType.VALIDATION_ERROR,
            false,
          );
        }
        validatedItems.push(item);
      }

      const subtotal = validatedItems.reduce(
        (sum, item) => sum + item.price * item.quantity, 0,
      );
      const tax = Math.round(subtotal * 0.0875 * 100) / 100;
      const total = Math.round((subtotal + tax) * 100) / 100;

      return this.success(
        {
          validated_items: validatedItems,
          item_count: validatedItems.length,
          subtotal,
          tax,
          total,
        },
        { processing_time_ms: Math.random() * 50 + 10 },
      );
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.HANDLER_ERROR,
        true,
      );
    }
  }
}
```

The handler receives a `StepContext` and returns a `StepHandlerResult` via
`this.success()` or `this.failure()`.

## Accessing Task Context

Use `getInput()` to read values from the task context (TAS-137 cross-language standard):

```typescript
// Get a typed value from the task context
const cartItems = context.getInput<CartItem[]>('cart_items');
const customerEmail = context.getInput<string>('customer_email');

// Get a nested object
const paymentInfo = context.getInput<PaymentInfo>('payment_info');
```

## Accessing Dependency Results

Use `getDependencyResult()` to read results from upstream steps. The return value
is auto-unwrapped — you get the result object directly:

```typescript
// Get the full result from an upstream step
const cartResult = context.getDependencyResult('validate_cart') as Record<string, unknown>;
const total = cartResult.total as number;

// Combine data from multiple upstream steps
const paymentResult = context.getDependencyResult('process_payment') as Record<string, unknown>;
const inventoryResult = context.getDependencyResult('update_inventory') as Record<string, unknown>;
```

## Error Handling

Return structured failures with error type and retryable flag:

```typescript
// Non-retryable validation failure
return this.failure(
  'Transaction exceeds single-transaction limit',
  ErrorType.VALIDATION_ERROR,
  false,
);

// Retryable transient failure
return this.failure(
  'Payment gateway temporarily unavailable',
  ErrorType.RETRYABLE_ERROR,
  true,
);

// Permanent business logic failure
return this.failure(
  'Customer email is required but was not provided',
  ErrorType.PERMANENT_ERROR,
  false,
);
```

Error types available via the `ErrorType` enum:

- `ErrorType.VALIDATION_ERROR` — Bad input data (non-retryable)
- `ErrorType.PERMANENT_ERROR` — Business logic rejection (non-retryable)
- `ErrorType.RETRYABLE_ERROR` — Transient failure (retryable)
- `ErrorType.HANDLER_ERROR` — Internal handler error

## Task Template Configuration

Generate a task template with `tasker-ctl`:

```bash
tasker-ctl template generate task_template \
  --language typescript \
  --param name=EcommerceOrderProcessing \
  --param namespace=ecommerce \
  --param handler_callable=Ecommerce.OrderProcessingHandler
```

This generates a YAML file defining the workflow. Here is a multi-step example from
the ecommerce example app:

```yaml
name: ecommerce_order_processing
namespace_name: ecommerce_ts
version: 1.0.0
description: "Complete e-commerce order processing workflow"
metadata:
  author: Bun Example Application
  tags:
    - namespace:ecommerce
    - pattern:order_processing
    - language:typescript
task_handler:
  callable: Ecommerce.OrderProcessingHandler
  initialization: {}
system_dependencies:
  primary: default
  secondary: []
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
        required: [sku, name, price, quantity]
    customer_email:
      type: string
      format: email
steps:
  - name: validate_cart
    description: "Validate cart items, calculate totals"
    handler:
      callable: Ecommerce.StepHandlers.ValidateCartHandler
    dependencies: []
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: process_payment
    description: "Process customer payment"
    handler:
      callable: Ecommerce.StepHandlers.ProcessPaymentHandler
    dependencies:
      - validate_cart
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: update_inventory
    description: "Reserve inventory for order items"
    handler:
      callable: Ecommerce.StepHandlers.UpdateInventoryHandler
    dependencies:
      - process_payment
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: create_order
    description: "Create order record"
    handler:
      callable: Ecommerce.StepHandlers.CreateOrderHandler
    dependencies:
      - update_inventory
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: send_confirmation
    description: "Send order confirmation email"
    handler:
      callable: Ecommerce.StepHandlers.SendConfirmationHandler
    dependencies:
      - create_order
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000
```

Key fields:

- **`metadata`** — Tags, authorship, and documentation links
- **`task_handler`** — The top-level handler and initialization config
- **`system_dependencies`** — External service connections the workflow requires
- **`input_schema`** — JSON Schema validating task input before execution
- **`steps[].handler.callable`** — Dot-separated handler name (e.g., `Ecommerce.StepHandlers.ValidateCartHandler`)
- **`steps[].dependencies`** — DAG edges defining execution order
- **`steps[].retry`** — Per-step retry policy with backoff

## Handler Variants

### API Handler (`step_handler_api`)

```bash
tasker-ctl template generate step_handler_api \
  --language typescript \
  --param name=FetchUser \
  --param base_url=https://api.example.com
```

Generates a handler that extends `ApiHandler`, providing `get`, `post`, `put`, `delete`
HTTP methods with automatic error classification using the native `fetch` API.

### Decision Handler (`step_handler_decision`)

```bash
tasker-ctl template generate step_handler_decision \
  --language typescript \
  --param name=RouteOrder
```

Generates a handler that extends `DecisionHandler`, providing `decisionSuccess()` for
routing workflows to different downstream step sets based on runtime conditions.

### Batchable Handler (`step_handler_batchable`)

```bash
tasker-ctl template generate step_handler_batchable \
  --language typescript \
  --param name=ProcessRecords
```

Generates a handler that extends `BatchableStepHandler` with an Analyzer/Worker pattern.
In analyzer mode it divides work into cursor ranges; in worker mode it processes
individual batches in parallel.

## Testing

The template generates a Vitest test file alongside the handler:

```typescript
import { describe, it, expect, vi } from 'vitest';
import { ValidateCartHandler } from '../validate-cart-handler';

describe('ValidateCartHandler', () => {
  const handler = new ValidateCartHandler();

  it('validates cart and returns totals', async () => {
    const context = {
      taskUuid: crypto.randomUUID(),
      stepUuid: crypto.randomUUID(),
      inputData: {
        cart_items: [
          { sku: 'SKU-001', name: 'Widget', price: 29.99, quantity: 2 },
        ],
      },
      dependencyResults: {},
      stepConfig: {},
      stepInputs: {},
      retryCount: 0,
      maxRetries: 3,
      getInput: vi.fn((key: string) =>
        key === 'cart_items'
          ? [{ sku: 'SKU-001', name: 'Widget', price: 29.99, quantity: 2 }]
          : undefined
      ),
      getDependencyResult: vi.fn(),
    } as any;

    const result = await handler.call(context);

    expect(result.success).toBe(true);
    expect(result.result?.total).toBeGreaterThan(0);
  });
});
```

Test handlers that use dependency results by configuring `getDependencyResult`:

```typescript
const contextWithDeps = {
  // ...base context fields
  getInput: vi.fn((key: string) =>
    key === 'customer_email' ? 'test@example.com' : undefined
  ),
  getDependencyResult: vi.fn((step: string) => ({
    validate_cart: { total: 64.79, validated_items: [] },
    process_payment: { payment_id: 'pay_abc', transaction_id: 'txn_xyz' },
    update_inventory: { updated_products: [], inventory_log_id: 'log_123' },
  }[step])),
} as any;
```

## Next Steps

- See the [Quick Start Guide](../guides/quick-start.md) for running the full workflow end-to-end
- See [Architecture](../architecture/index.md) for system design details
- Browse the [Bun example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app) for complete handler implementations
