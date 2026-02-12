# TypeScript Guide

This guide covers using Tasker with TypeScript step handlers via the `@tasker-systems/tasker` package.

## Quick Start

```bash
# Install with npm
npm install @tasker-systems/tasker

# Or with Bun (recommended)
bun add @tasker-systems/tasker
```

## Writing a Step Handler

TypeScript step handlers extend the `StepHandler` base class:

```typescript path=null start=null
import { StepHandler } from '@tasker-systems/tasker';
import type { StepContext } from '@tasker-systems/tasker';
import type { StepHandlerResult } from '@tasker-systems/tasker';

class MyHandler extends StepHandler {
  static handlerName = 'my_handler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    return this.success({ processed: true });
  }
}
```

### Minimal Handler Example

```typescript path=null start=null
import { StepHandler, StepHandlerResult, ErrorType } from '@tasker-systems/tasker';
import type { StepContext } from '@tasker-systems/tasker';

class LinearStep1Handler extends StepHandler {
  static handlerName = 'linear_step_1';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    // Access task context using getInput()
    const evenNumber = context.getInput<number>('even_number');

    if (!evenNumber || evenNumber % 2 !== 0) {
      return this.failure(
        'Task context must contain an even number',
        ErrorType.VALIDATION_ERROR,
        false  // not retryable
      );
    }

    // Perform business logic
    const result = evenNumber * evenNumber;

    // Return success result
    return this.success(
      { result },
      {
        operation: 'square',
        step_type: 'initial'
      }
    );
  }
}
```

### Accessing Task Context

Use `getInput()` for task context access (cross-language standard API):

```typescript path=null start=null
// Get typed value from task context
const customerId = context.getInput<string>('customer_id');

// Get with default value
const batchSize = context.getInputOr('batch_size', 100);

// Access raw input data
const items = context.inputData['items'] as CartItem[];
```

### Accessing Dependency Results

Access results from upstream steps using `getDependencyResult()`:

```typescript path=null start=null
// Get unwrapped result from upstream step
const previousResult = context.getDependencyResult('previous_step_name');

// Extract nested field from dependency result
const orderTotal = context.getDependencyField('validate_order', 'order_total');

// Get all results matching a prefix (for batch workers)
const batchResults = context.getAllDependencyResults('process_batch_');
```

## Complete Example: Process Order Handler

This example shows a real-world e-commerce handler:

```typescript path=null start=null
import { StepHandler, StepHandlerResult, ErrorType } from '@tasker-systems/tasker';
import type { StepContext } from '@tasker-systems/tasker';

interface ValidatedItem {
  product_id: number;
  name: string;
  price: number;
  quantity: number;
  line_total: number;
}

interface ValidationResult {
  validated_items: ValidatedItem[];
  subtotal: number;
  tax: number;
  shipping: number;
  total: number;
}

// Mock product database
const PRODUCTS: Record<number, { name: string; price: number; stock: number; active: boolean }> = {
  1: { name: 'Widget A', price: 29.99, stock: 100, active: true },
  2: { name: 'Widget B', price: 49.99, stock: 50, active: true },
  3: { name: 'Widget C', price: 19.99, stock: 25, active: true },
};

class ValidateCartHandler extends StepHandler {
  static handlerName = 'ecommerce.step_handlers.ValidateCartHandler';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    // TAS-137: Use getInput() for task context access
    const cartItems = context.getInput<Array<{ product_id: number; quantity: number }>>('cart_items');

    if (!cartItems || cartItems.length === 0) {
      return this.failure(
        'Cart items are required',
        ErrorType.VALIDATION_ERROR,
        false,
        undefined,
        'MISSING_CART_ITEMS'
      );
    }

    console.log(`ValidateCartHandler: Validating ${cartItems.length} items`);

    // Validate and calculate totals
    const validatedItems: ValidatedItem[] = [];

    for (const [index, item] of cartItems.entries()) {
      if (!item.product_id) {
        return this.failure(
          `Product ID required for item ${index + 1}`,
          ErrorType.VALIDATION_ERROR,
          false,
          undefined,
          'MISSING_PRODUCT_ID'
        );
      }

      if (!item.quantity || item.quantity <= 0) {
        return this.failure(
          `Valid quantity required for item ${index + 1}`,
          ErrorType.VALIDATION_ERROR,
          false,
          undefined,
          'INVALID_QUANTITY'
        );
      }

      const product = PRODUCTS[item.product_id];

      if (!product) {
        return this.failure(
          `Product ${item.product_id} not found`,
          ErrorType.VALIDATION_ERROR,
          false,
          undefined,
          'PRODUCT_NOT_FOUND'
        );
      }

      if (!product.active) {
        return this.failure(
          `Product ${product.name} is not available`,
          ErrorType.VALIDATION_ERROR,
          false,
          undefined,
          'PRODUCT_INACTIVE'
        );
      }

      if (product.stock < item.quantity) {
        // Retryable - stock might be replenished
        return this.failure(
          `Insufficient stock for ${product.name}`,
          ErrorType.RESOURCE_UNAVAILABLE,
          true,  // retryable
          {
            product_id: item.product_id,
            available: product.stock,
            requested: item.quantity,
          },
          'INSUFFICIENT_STOCK'
        );
      }

      validatedItems.push({
        product_id: product_id,
        name: product.name,
        price: product.price,
        quantity: item.quantity,
        line_total: Math.round(product.price * item.quantity * 100) / 100,
      });
    }

    // Calculate totals
    const subtotal = validatedItems.reduce((sum, item) => sum + item.line_total, 0);
    const tax = Math.round(subtotal * 0.08 * 100) / 100;  // 8% tax
    const shipping = this.calculateShipping(validatedItems);
    const total = subtotal + tax + shipping;

    return this.success(
      {
        validated_items: validatedItems,
        subtotal,
        tax,
        shipping,
        total,
        item_count: validatedItems.length,
        validated_at: new Date().toISOString(),
      },
      {
        operation: 'validate_cart',
        execution_hints: {
          items_validated: validatedItems.length,
          total_amount: total,
        },
      }
    );
  }

  private calculateShipping(items: ValidatedItem[]): number {
    const totalWeight = items.reduce((sum, item) => sum + item.quantity * 0.5, 0);
    if (totalWeight <= 2) return 5.99;
    if (totalWeight <= 10) return 9.99;
    return 14.99;
  }
}

export default ValidateCartHandler;
```

## Error Handling

Use the `ErrorType` enum and return structured failures:

```typescript path=null start=null
import { ErrorType } from '@tasker-systems/tasker';

// Non-retryable validation error
return this.failure(
  'Invalid order data',
  ErrorType.VALIDATION_ERROR,
  false,  // not retryable
  { field: 'customer_id' },
  'VALIDATION_ERROR'
);

// Retryable transient error
return this.failure(
  'Payment gateway timeout',
  ErrorType.NETWORK_ERROR,
  true,  // retryable
  { gateway: 'stripe', timeout_ms: 30000 },
  'GATEWAY_TIMEOUT'
);
```

### Error Types

```typescript path=null start=null
enum ErrorType {
  HANDLER_ERROR = 'handler_error',
  VALIDATION_ERROR = 'validation_error',
  NETWORK_ERROR = 'network_error',
  RESOURCE_UNAVAILABLE = 'resource_unavailable',
  TIMEOUT = 'timeout',
  PERMANENT_ERROR = 'permanent_error',
}
```

## Task Template Configuration

Define workflows in YAML:

```yaml path=null start=null
name: checkout_workflow
namespace_name: ecommerce
version: 1.0.0
description: "E-commerce checkout workflow"

steps:
  - name: validate_cart
    handler:
      callable: ecommerce.step_handlers.ValidateCartHandler
    dependencies: []

  - name: process_payment
    handler:
      callable: ecommerce.step_handlers.ProcessPaymentHandler
    dependencies:
      - validate_cart

  - name: update_inventory
    handler:
      callable: ecommerce.step_handlers.UpdateInventoryHandler
    dependencies:
      - validate_cart

  - name: send_confirmation
    handler:
      callable: ecommerce.step_handlers.SendConfirmationHandler
    dependencies:
      - process_payment
      - update_inventory
```

## Handler Registration

Register handlers using the registry:

```typescript path=null start=null
import { HandlerRegistry } from '@tasker-systems/tasker';

const registry = new HandlerRegistry();
registry.register(ValidateCartHandler);
registry.register(ProcessPaymentHandler);

// Or register with explicit name
registry.registerWithName('custom_name', CustomHandler);
```

## Testing

Write tests using your preferred test framework (Bun, Jest, Vitest):

```typescript path=null start=null
import { describe, test, expect } from 'bun:test';
import ValidateCartHandler from './validate-cart-handler';
import { buildTestContext } from '@tasker-systems/tasker/testing';

describe('ValidateCartHandler', () => {
  test('validates cart successfully', async () => {
    const handler = new ValidateCartHandler();
    const context = buildTestContext({
      inputData: {
        cart_items: [
          { product_id: 1, quantity: 2 }
        ]
      }
    });

    const result = await handler.call(context);

    expect(result.success).toBe(true);
    expect(result.result?.total).toBeCloseTo(70.77, 2);
  });

  test('rejects empty cart', async () => {
    const handler = new ValidateCartHandler();
    const context = buildTestContext({
      inputData: { cart_items: [] }
    });

    const result = await handler.call(context);

    expect(result.success).toBe(false);
    expect(result.error_code).toBe('MISSING_CART_ITEMS');
  });

  test('handles out of stock as retryable', async () => {
    const handler = new ValidateCartHandler();
    const context = buildTestContext({
      inputData: {
        cart_items: [
          { product_id: 1, quantity: 1000 }
        ]
      }
    });

    const result = await handler.call(context);

    expect(result.success).toBe(false);
    expect(result.retryable).toBe(true);
    expect(result.error_code).toBe('INSUFFICIENT_STOCK');
  });
});
```

Run tests:

```bash
# Bun
bun test

# npm
npm test
```

## Common Patterns

### Type-Safe Context Access

```typescript path=null start=null
// TAS-137: Cross-language standard API
const value = context.getInput<string>('field_name');

// Get with default value
const batchSize = context.getInputOr('batch_size', 100);

// Type-safe generic access
interface OrderData {
  customer_id: string;
  items: Array<{ product_id: number; quantity: number }>;
}
const order = context.getInput<OrderData>('order');
```

### Dependency Result Access

```typescript path=null start=null
// Get unwrapped result from upstream step
const result = context.getDependencyResult('step_name');

// Extract nested field
const value = context.getDependencyField('step_name', 'nested', 'field');

// Get all keys
const keys = context.getDependencyResultKeys();
```

### Metadata for Observability

```typescript path=null start=null
return this.success(
  { data: processedData },
  {
    operation: 'my_operation',
    input_refs: {
      field: 'context.getInput("field")'
    },
    execution_hints: {
      items_processed: 100,
      duration_ms: 250
    }
  }
);
```

### Handler with Dependencies

```typescript path=null start=null
class ProcessPaymentHandler extends StepHandler {
  static handlerName = 'process_payment';

  async call(context: StepContext): Promise<StepHandlerResult> {
    // Get results from upstream steps
    const cartResult = context.getDependencyResult('validate_cart') as {
      total: number;
      validated_items: ValidatedItem[];
    };

    const total = cartResult.total;

    // Get payment info from task context
    const paymentMethod = context.getInput<string>('payment_method');
    const paymentToken = context.getInput<string>('payment_token');

    // Process payment
    const paymentId = await this.chargePayment(total, paymentMethod, paymentToken);

    return this.success({
      payment_id: paymentId,
      amount_charged: total,
      status: 'completed'
    });
  }

  private async chargePayment(
    amount: number,
    method: string,
    token: string
  ): Promise<string> {
    // Implementation...
    return `pay_${Date.now()}`;
  }
}
```

### Batch Processing with Checkpoints

```typescript path=null start=null
class BatchProcessHandler extends StepHandler {
  static handlerName = 'batch_process';

  async call(context: StepContext): Promise<StepHandlerResult> {
    // Check for existing checkpoint
    let cursor: number;
    let accumulated: { total: number; processed: number };

    if (context.hasCheckpoint()) {
      cursor = context.checkpointCursor as number;
      accumulated = context.accumulatedResults as typeof accumulated || { total: 0, processed: 0 };
    } else {
      cursor = 0;
      accumulated = { total: 0, processed: 0 };
    }

    // Process batch
    const batchSize = context.getInputOr('batch_size', 100);
    const items = await this.fetchItems(cursor, batchSize);

    for (const item of items) {
      accumulated.total += item.value;
      accumulated.processed += 1;
    }

    if (items.length < batchSize) {
      // All done
      return this.success(accumulated);
    } else {
      // More to process - yield checkpoint
      return StepHandlerResult.checkpoint(
        cursor + batchSize,
        accumulated.processed,
        accumulated
      );
    }
  }

  private async fetchItems(cursor: number, limit: number): Promise<Array<{ value: number }>> {
    // Implementation...
    return [];
  }
}
```

## Runtime Support

The `@tasker-systems/tasker` package works with:

- **Bun** (recommended) - Native TypeScript execution
- **Node.js** (18+) - Requires transpilation
- **Deno** - Native TypeScript support

```typescript path=null start=null
// server.ts - Worker entry point
import { WorkerBootstrap } from '@tasker-systems/tasker';

const config = {
  namespace: 'ecommerce',
  handlers: [ValidateCartHandler, ProcessPaymentHandler],
};

await WorkerBootstrap.start(config);
```

## Submitting Tasks via Client SDK

The `@tasker-systems/tasker` package includes FFI bindings to the orchestration client API:

```typescript path=null start=null
import { getRuntime, type ClientResult } from '@tasker-systems/tasker';

async function submitTask() {
  const runtime = getRuntime();

  // Bootstrap the worker (initializes client connection)
  const bootstrapResult = runtime.bootstrapWorker();
  if (bootstrapResult.status !== 'started') {
    throw new Error('Bootstrap failed');
  }

  // Create a task
  const request = {
    name: 'order_fulfillment',
    namespace: 'ecommerce',
    version: '1.0.0',
    context: {
      customer: { id: 123, email: 'customer@example.com' },
      items: [
        { product_id: 1, quantity: 2, price: 29.99 }
      ]
    },
    initiator: 'my-service',
    source_system: 'api',
    reason: 'New order received',
  };

  const createResult: ClientResult = runtime.clientCreateTask(JSON.stringify(request));
  if (!createResult.success) {
    throw new Error(`Failed to create task: ${createResult.error}`);
  }

  const taskResponse = createResult.data;
  console.log(`Task created: ${taskResponse.task_uuid}`);

  // Get task status
  const getResult = runtime.clientGetTask(taskResponse.task_uuid);
  if (getResult.success) {
    console.log(`Task status: ${getResult.data.status}`);
  }

  // List task steps
  const stepsResult = runtime.clientListTaskSteps(taskResponse.task_uuid);
  if (stepsResult.success) {
    for (const step of stepsResult.data) {
      console.log(`Step ${step.name}: ${step.current_state}`);
    }
  }

  // Check health
  const healthResult = runtime.clientHealthCheck();
  console.log(`API healthy: ${healthResult.success}`);
}
```

### Available Client Methods

| Method | Description |
|--------|-------------|
| `clientCreateTask(requestJson)` | Create a new task |
| `clientGetTask(uuid)` | Get task by UUID |
| `clientListTasks(paramsJson)` | List tasks with filters |
| `clientCancelTask(uuid)` | Cancel a task |
| `clientListTaskSteps(taskUuid)` | List workflow steps |
| `clientGetStep(taskUuid, stepUuid)` | Get specific step |
| `clientGetStepAuditHistory(taskUuid, stepUuid)` | Get step audit trail |
| `clientHealthCheck()` | Check API health |

All methods return a `ClientResult` with `success`, `data`, `error`, and `recoverable` fields.

## Next Steps

- See [Architecture](../architecture/README.md) for system design
- See [Workers Reference](../workers/README.md) for advanced patterns
- See the [tasker-core workers/typescript](https://github.com/tasker-systems/tasker-core/tree/main/workers/typescript) for complete examples
