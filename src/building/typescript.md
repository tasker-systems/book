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

This creates a DSL-style handler with typed inputs that delegates to a service function.

## Writing a Handler (DSL)

Every handler follows the three-layer pattern: **type definition**, **handler declaration**, **service delegation**.

```typescript
// src/services/types.ts — the contract
export interface CartItem {
  sku: string;
  name: string;
  price: number;
  quantity: number;
}

// src/handlers/ecommerce.ts — the handler
import { defineHandler } from '@tasker-systems/tasker';
import type { CartItem } from '../services/types';
import * as svc from '../services/ecommerce';

export const ValidateCartHandler = defineHandler(
  'Ecommerce.StepHandlers.ValidateCartHandler',
  { inputs: { cartItems: 'cart_items' } },
  async ({ cartItems }) => svc.validateCartItems(cartItems as CartItem[] | undefined),
);
```

The `defineHandler` factory registers a handler by name. The `inputs` config maps camelCase parameter names to snake\_case YAML field names. The async callback receives typed arguments and delegates to a service function.

## Type System

TypeScript handlers use standard **interfaces** for both input and result types. The DSL injects values from the task context and upstream results as plain objects matching these interfaces.

**Input types**:

```typescript
export interface CartItem {
  sku: string;
  name: string;
  price: number;
  quantity: number;
}

export interface PaymentInfo {
  method: string;
  card_last_four?: string;
  token: string;
  amount: number;
}
```

**Result types** describe what a handler returns (used by downstream `depends`):

```typescript
export interface EcommerceValidateCartResult {
  [key: string]: unknown;
  validated_items: CartItem[];
  item_count: number;
  subtotal: number;
  tax: number;
  total: number;
}

export interface EcommerceProcessPaymentResult {
  [key: string]: unknown;
  payment_id: string;
  transaction_id: string;
  amount_charged: number;
  status: string;
}
```

The `[key: string]: unknown` index signature allows result objects to carry additional fields without type errors when accessing known fields.

## Accessing Task Context

The `inputs` config in `defineHandler` extracts fields from the task context. Each entry maps a camelCase parameter name to the snake\_case field name in the submitted JSON:

```typescript
export const ValidateCartHandler = defineHandler(
  'Ecommerce.StepHandlers.ValidateCartHandler',
  { inputs: { cartItems: 'cart_items' } },
  async ({ cartItems }) => svc.validateCartItems(cartItems as CartItem[] | undefined),
);
```

The callback receives `cartItems` directly — no need to parse raw JSON.

## Working with Dependencies

The `depends` config injects results from upstream steps. Each entry maps a camelCase parameter name to the upstream step name:

```typescript
export const ProcessPaymentHandler = defineHandler(
  'Ecommerce.StepHandlers.ProcessPaymentHandler',
  {
    depends: { cartResult: 'validate_cart' },
    inputs: { paymentInfo: 'payment_info' },
  },
  async ({ cartResult, paymentInfo }) =>
    svc.processPayment(
      cartResult as Record<string, unknown>,
      paymentInfo as PaymentInfo | undefined,
    ),
);
```

Handlers can reference **any ancestor step** in the DAG — not just direct predecessors. Here's a convergence handler that accesses three upstream steps plus task inputs:

```typescript
export const CreateOrderHandler = defineHandler(
  'Ecommerce.StepHandlers.CreateOrderHandler',
  {
    depends: {
      cartResult: 'validate_cart',
      paymentResult: 'process_payment',
      inventoryResult: 'update_inventory',
    },
    inputs: { customerEmail: 'customer_email' },
  },
  async ({ cartResult, paymentResult, inventoryResult, customerEmail }) =>
    svc.createOrder(
      cartResult as Record<string, unknown>,
      paymentResult as Record<string, unknown>,
      inventoryResult as Record<string, unknown>,
      customerEmail as string | undefined,
    ),
);
```

## Multi-Step Example: Data Pipeline

The data pipeline workflow demonstrates a parallel DAG — three independent extract branches, each feeding its own transform, converging at aggregation:

```text
extract_sales    extract_inventory    extract_customers
     │                  │                    │
     ▼                  ▼                    ▼
transform_sales  transform_inventory  transform_customers
     │                  │                    │
     └──────────────────┼────────────────────┘
                        ▼
               aggregate_metrics
                        │
                        ▼
              generate_insights
```

TypeScript handlers follow the same concise pattern:

```typescript
import { defineHandler } from '@tasker-systems/tasker';
import type {
  PipelineExtractSalesResult,
  PipelineTransformSalesResult,
  PipelineTransformInventoryResult,
  PipelineTransformCustomersResult,
} from '../services/types';
import * as svc from '../services/data_pipeline';

// Extract — no dependencies, runs in parallel
export const ExtractSalesDataHandler = defineHandler(
  'DataPipeline.StepHandlers.ExtractSalesDataHandler',
  { inputs: { source: 'source', dateRangeStart: 'date_range_start' } },
  async ({ source, dateRangeStart }) =>
    svc.extractSalesData(source as string, dateRangeStart as string | undefined),
);

// Transform — depends on one extract branch
export const TransformSalesHandler = defineHandler(
  'DataPipeline.StepHandlers.TransformSalesHandler',
  { depends: { salesData: 'extract_sales_data' } },
  async ({ salesData }) =>
    svc.transformSales(salesData as PipelineExtractSalesResult),
);

// Aggregate — converges three transform branches
export const AggregateMetricsHandler = defineHandler(
  'DataPipeline.StepHandlers.AggregateMetricsHandler',
  {
    depends: {
      salesTransform: 'transform_sales',
      inventoryTransform: 'transform_inventory',
      customersTransform: 'transform_customers',
    },
  },
  async ({ salesTransform, inventoryTransform, customersTransform }) =>
    svc.aggregateMetrics(
      salesTransform as PipelineTransformSalesResult,
      inventoryTransform as PipelineTransformInventoryResult,
      customersTransform as PipelineTransformCustomersResult,
    ),
);
```

## Error Handling

Throw `PermanentError` or `RetryableError` from your handler or service functions:

```typescript
import { PermanentError, RetryableError } from '@tasker-systems/tasker';

// Non-retryable validation failure
throw new PermanentError('Payment declined: insufficient funds', 'PAYMENT_DECLINED');

// Retryable transient failure
throw new RetryableError('Payment gateway temporarily unavailable', 'GATEWAY_ERROR');
```

## Testing

DSL handlers are exported constants — test them with Vitest by calling the handler's async callback directly, or by testing the service functions:

```typescript
import { describe, it, expect, vi } from 'vitest';
import * as svc from '../services/ecommerce';

describe('ValidateCartHandler', () => {
  it('delegates to service', async () => {
    const mockResult = { validated_items: [], total: 64.79 };
    vi.spyOn(svc, 'validateCartItems').mockResolvedValue(mockResult);

    const cartItems = [{ sku: 'SKU-001', name: 'Widget', price: 29.99, quantity: 2 }];
    const result = await svc.validateCartItems(cartItems);

    expect(result.total).toBe(64.79);
  });
});
```

For handlers with dependencies, test the service functions with typed arguments:

```typescript
describe('CreateOrderHandler', () => {
  it('creates order from upstream data', async () => {
    const mockResult = { order_id: 'ORD-001' };
    vi.spyOn(svc, 'createOrder').mockResolvedValue(mockResult);

    const result = await svc.createOrder(
      { total: 64.79, validated_items: [] },
      { payment_id: 'pay_abc', transaction_id: 'txn_xyz' },
      { inventory_log_id: 'log_123' },
      'test@example.com',
    );

    expect(result.order_id).toBe('ORD-001');
  });
});
```

Because handlers delegate to service functions, you can test the services directly without any Tasker infrastructure.

## Handler Variants

### API Handler

Adds HTTP client methods with error classification using the native `fetch` API. Extends `ApiHandler` with the class-based pattern. See [Class-Based Handlers — API Handler](../reference/class-based-handlers.md#api-handler).

### Decision Handler

Adds workflow routing with `decisionSuccess()` for activating downstream step sets. Extends `DecisionHandler` with the class-based pattern. See [Conditional Workflows](../guides/conditional-workflows.md).

### Batchable Handler

Adds batch processing with Analyzer/Worker pattern using `BatchableStepHandler`. See [Class-Based Handlers — Batchable Handler](../reference/class-based-handlers.md#batchable-handler) and [Batch Processing](../guides/batch-processing.md).

## Class-Based Alternative

If you prefer class inheritance, all handler types support a class-based pattern where you extend `StepHandler` and implement `async call(context)`. See [Class-Based Handlers](../reference/class-based-handlers.md) for the full reference.

## Next Steps

- [Your First Workflow](first-workflow.md) — Build a multi-step DAG end-to-end
- [Architecture](../architecture/index.md) — System design details
- [Bun example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app) — Complete working implementation
