# Handler Types

Tasker provides four handler types that cover the most common workflow patterns. The DSL approach lets you declare what a handler receives — typed inputs and dependency results — while your business logic stays in your service layer.

## Cross-Language Availability

| Handler Type | Python | Ruby | TypeScript | Rust |
|---|---|---|---|---|
| **Step Handler** | Yes | Yes | Yes | Yes |
| **API Handler** | Yes | Yes | Yes | -- |
| **Decision Handler** | Yes | Yes | Yes | -- |
| **Batchable Handler** | Yes | Yes | Yes | -- |

Rust provides only the base Step Handler trait, composing capability traits instead. See [Rust's Handler Architecture](#rusts-handler-architecture) below.

## Step Handler (DSL)

The base handler type. All other types extend it.

**When to use**: General-purpose business logic — database operations, calculations, transformations, service calls, or anything that takes input and produces output.

### Python

```python
from tasker_core.step_handler.functional import inputs, step_handler
from app.services.types import EcommerceOrderInput
from app.services import ecommerce as svc

@step_handler("validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context: StepContext):
    return svc.validate_cart_items(inputs.resolved_items)
```

### Ruby

```ruby
extend TaskerCore::StepHandler::Functional

ValidateCartHandler = step_handler(
  'Ecommerce::StepHandlers::ValidateCartHandler',
  inputs: Types::Ecommerce::OrderInput
) do |inputs:, context:|
  Ecommerce::Service.validate_cart_items(cart_items: inputs.cart_items)
end
```

### TypeScript

```typescript
import { defineHandler } from '@tasker-systems/tasker';
import * as svc from '../services/ecommerce';

export const ValidateCartHandler = defineHandler(
  'Ecommerce.StepHandlers.ValidateCartHandler',
  { inputs: { cartItems: 'cart_items' } },
  async ({ cartItems }) => svc.validateCartItems(cartItems as CartItem[]),
);
```

> For the class-based alternative, see [Class-Based Handlers](../reference/class-based-handlers.md).

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate step_handler \
  --plugin tasker-contrib-python \
  --param name=ProcessPayment
```

Available for all four languages: `tasker-contrib-rails`, `tasker-contrib-python`, `tasker-contrib-typescript`, `tasker-contrib-rust`.

**See it in action**: All five workflows in the [example apps](example-apps.md) use step handlers. Start with the e-commerce checkout ([Post 01](../stories/post-01-ecommerce-checkout.md)) for the simplest example.

**Next**: [Your First Handler](../building/first-handler.md) walks through writing and registering a step handler end-to-end.

## What the DSL Composes

The DSL builds a typed method signature from two sources:

| Decorator / Config | Source | What it provides |
|---|---|---|
| `@inputs(Model)` / `inputs:` | Task context (submitted data) | Typed input fields |
| `@depends_on(name=("step", Model))` / `depends:` | Upstream step results | Typed dependency results |

Both are injected as function parameters. Your handler receives typed objects — not raw dicts or JSON — and delegates to a service function that contains the actual business logic.

Here's a handler that uses both:

```python
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
```

The handler declares *what it needs*; Tasker resolves *how to get it*.

## Type System by Language

Each language uses its native type system for input and result models:

| | Python | Ruby | TypeScript |
|---|---|---|---|
| **Library** | Pydantic `BaseModel` | `Dry::Struct` | TypeScript interfaces |
| **Validation** | `@model_validator` | `validate!` method | Manual type guards |
| **Optional fields** | `field: str \| None = None` | `attribute :field, Types::String.optional` | `field?: string` |
| **Field aliases** | `@property` methods | Attribute readers | Getter functions |
| **Error on invalid** | Raises `PermanentError` | Raises `PermanentError` | Throws `PermanentError` |

**Python** (Pydantic BaseModel):

```python
class EcommerceOrderInput(BaseModel):
    items: list[dict[str, Any]] | None = None        # submitted as "items"
    cart_items: list[dict[str, Any]] | None = None    # or "cart_items"
    customer_email: str | None = None
    payment_token: str | None = None

    @property
    def resolved_items(self) -> list[dict[str, Any]]:
        """Accept either field name from the task context."""
        return self.items or self.cart_items or []
```

**Ruby** (Dry::Struct):

```ruby
module Types
  module Ecommerce
    class OrderInput < Types::InputStruct
      attribute :cart_items, Types::Array.of(Types::Hash).optional
      attribute :customer_email, Types::String.optional
      attribute :payment_token, Types::String.optional
    end
  end
end
```

**TypeScript** (interfaces):

```typescript
interface CartItem {
  sku: string;
  name: string;
  price: number;
  quantity: number;
}
```

## Specialized Handler Patterns

### API Handler

Adds HTTP client methods with built-in error classification. The `APIMixin` provides `self.get()`, `self.post()`, etc. with automatic retryable/permanent error detection.

**When to use**: Calling external APIs where you need to distinguish retryable errors (5xx, timeouts) from permanent errors (4xx).

API handlers currently use the class-based pattern with mixin composition. See [Class-Based Handlers — API Handler](../reference/class-based-handlers.md#api-handler) for the full pattern.

### Decision Handler

Adds workflow routing methods. `decision_success()` activates downstream steps by name; `skip_branches()` when no steps should execute.

**When to use**: Conditional branching — when the next steps depend on runtime data.

```python
from tasker_core.step_handler.functional import decision_handler

@decision_handler("order_routing")
def order_routing(context: StepContext):
    order_type = context.get_input("order_type")
    if order_type == "premium":
        return ["validate_premium", "process_premium"]
    return ["standard_processing"]
```

See [Conditional Workflows](../guides/conditional-workflows.md) for decision handler patterns in depth.

### Batchable Handler

Adds batch processing for splitting large workloads into parallel cursor-based batches.

**When to use**: Processing large datasets where you want to divide work across multiple parallel workers.

**Workflow pattern**: Analyzer → parallel Workers → optional Aggregator.

Batchable handlers currently use the class-based pattern due to their stateful nature (cursor management, batch context). See [Class-Based Handlers — Batchable Handler](../reference/class-based-handlers.md#batchable-handler) for the full pattern, and [Batch Processing](../guides/batch-processing.md) for the production guide.

## Task Templates

All handler types are wired together using YAML task template definitions. A task template defines the DAG — which steps to run, their dependencies, and which handlers to invoke.

```yaml
name: order_processing
namespace: ecommerce
version: "1.0.0"
description: "Order processing workflow"

step_templates:
  - name: validate_order
    description: "Validate the incoming order"
    handler:
      callable: ValidateOrderHandler
      initialization: {}
    depends_on_step_name: []
    retry:
      max_attempts: 3
      backoff_strategy: exponential
      backoff_base_seconds: 2
```

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate task_template \
  --plugin tasker-contrib-python \
  --param name=OrderProcessing \
  --param namespace=ecommerce
```

Task templates are language-agnostic — the same YAML structure works across all four languages. The `handler.callable` field maps to the handler's registered name or class path.

For a complete walkthrough of building a multi-step workflow with templates, see [Your First Workflow](../building/first-workflow.md).

## Rust's Handler Architecture

Rust provides `RustStepHandler` as its single handler trait — but this is not a limitation. The Rust worker crate defines **capability traits** in `handler_capabilities.rs` that Rust handlers compose directly:

| Capability Trait | What it provides |
|---|---|
| `APICapable` | HTTP client methods with retryable/permanent error classification |
| `DecisionCapable` | Workflow routing via step activation |
| `BatchableCapable` | Cursor-based parallel batch processing |

A Rust handler implements `RustStepHandler` and adds any capability traits it needs. This is idiomatic Rust — trait composition instead of class inheritance. For a complex example that combines multiple capabilities, see `diamond_decision_batch.rs` in the Rust worker crate.

In fact, the Rust `batch_processing` module is the **foundation** that Python, Ruby, and TypeScript access through FFI. The specialized handler types in those languages are ergonomic wrappers around the Rust implementation — Rust developers work with the underlying traits directly.
