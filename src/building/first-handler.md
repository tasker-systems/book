# Your First Handler

This guide walks you through writing your first step handler using the DSL.

## What is a Handler?

A **Step Handler** is your code that executes business logic for a single workflow step. With the DSL, a handler declares what it receives — typed inputs from the task context and typed results from upstream steps — and delegates to a service function. Handlers are thin wrappers: Tasker handles sequencing, retries, and error classification; your service layer handles the business logic.

You can generate a handler from a template with `tasker-ctl`:

```bash
tasker-ctl template generate step_handler --language python --param name=ProcessOrder
```

Or write one from scratch using the patterns below.

## The DSL Approach

Every handler follows the same three-layer pattern:

1. **Type definition** — the contract (what the handler receives and returns)
2. **Handler declaration** — the DSL wiring (which step, which inputs, which dependencies)
3. **Service delegation** — one-line call to your business logic

### Python

```python
# app/services/types.py — the contract
class EcommerceOrderInput(BaseModel):
    items: list[dict[str, Any]] | None = None        # submitted as "items"
    cart_items: list[dict[str, Any]] | None = None    # or "cart_items"
    customer_email: str | None = None
    payment_token: str | None = None

    @property
    def resolved_items(self) -> list[dict[str, Any]]:
        """Accept either field name from the task context."""
        return self.items or self.cart_items or []

# app/handlers/ecommerce.py — the handler
from tasker_core.step_handler.functional import inputs, step_handler
from app.services.types import EcommerceOrderInput
from app.services import ecommerce as svc

@step_handler("validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context: StepContext):
    return svc.validate_cart_items(inputs.resolved_items)
```

The `@step_handler` decorator registers this function as the handler for the `validate_cart` step. The `@inputs` decorator tells Tasker to extract the task context into an `EcommerceOrderInput` Pydantic model. The function body is a single service call.

### Ruby

```ruby
# app/services/types.rb — the contract
module Types
  module Ecommerce
    class OrderInput < Types::InputStruct
      attribute :cart_items, Types::Array.of(Types::Hash).optional
      attribute :customer_email, Types::String.optional
    end
  end
end

# app/handlers/ecommerce/step_handlers/validate_cart_handler.rb — the handler
module Ecommerce
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ValidateCartHandler = step_handler(
      'Ecommerce::StepHandlers::ValidateCartHandler',
      inputs: Types::Ecommerce::OrderInput
    ) do |inputs:, context:|
      Ecommerce::Service.validate_cart_items(cart_items: inputs.cart_items)
    end
  end
end
```

Ruby uses `step_handler` as a method that takes a block. The `inputs:` keyword argument receives a `Dry::Struct` instance with typed attributes.

### TypeScript

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
import * as svc from '../services/ecommerce';

export const ValidateCartHandler = defineHandler(
  'Ecommerce.StepHandlers.ValidateCartHandler',
  { inputs: { cartItems: 'cart_items' } },
  async ({ cartItems }) => svc.validateCartItems(cartItems as CartItem[]),
);
```

TypeScript uses `defineHandler` as a factory function. The `inputs` config maps camelCase parameter names to snake\_case YAML field names.

### Rust

Rust uses the `RustStepHandler` trait directly — this is Rust's only handler pattern. There is no DSL equivalent, by design.

```rust
use anyhow::Result;
use async_trait::async_trait;
use serde_json::json;
use std::time::Instant;
use tasker_shared::messaging::StepExecutionResult;
use tasker_shared::types::TaskSequenceStep;
use tasker_worker_rust::{success_result, RustStepHandler};
use tasker_worker_rust::step_handlers::StepHandlerConfig;

pub struct ProcessOrderHandler {
    config: StepHandlerConfig,
}

#[async_trait]
impl RustStepHandler for ProcessOrderHandler {
    fn new(config: StepHandlerConfig) -> Self {
        Self { config }
    }

    fn name(&self) -> &str {
        "process_order"
    }

    async fn call(
        &self,
        step_data: &TaskSequenceStep,
    ) -> Result<StepExecutionResult> {
        let start = Instant::now();
        let _input_data = &step_data.task.context;

        let result_data = json!({
            "processed": true,
            "handler": "process_order"
        });

        let duration_ms = start.elapsed().as_millis() as i64;

        Ok(success_result(
            step_data.workflow_step.workflow_step_uuid,
            result_data,
            duration_ms,
            None,
        ))
    }
}
```

## Reading the DSL

Each language's DSL has the same three concepts:

| Concept | Python | Ruby | TypeScript |
|---------|--------|------|------------|
| Register a handler | `@step_handler("name")` | `step_handler('Name', ...) do` | `defineHandler('Name', ...)` |
| Inject task inputs | `@inputs(Model)` | `inputs: Model` | `{ inputs: { key: 'field' } }` |
| Inject dependency results | `@depends_on(x=("step", Model))` | `depends_on: { x: ['step', Model] }` | `{ depends: { x: 'step' } }` |

The handler function always receives `context` as its last parameter — a `StepContext` with execution metadata. Most handlers don't need it directly, but it's available for advanced patterns.

## Registering Handlers

Handlers are resolved by matching the `handler.callable` field in task template YAML. The callable format varies by language:

| Language | Format | Example |
|----------|--------|---------|
| Ruby | `Module::ClassName` | `Ecommerce::StepHandlers::ValidateCartHandler` |
| Python | `function_name` | `validate_cart` |
| TypeScript | `Namespace.ClassName` | `Ecommerce.StepHandlers.ValidateCartHandler` |
| Rust | `function_name` | `process_order` |

## Class-Based Alternative

If you prefer class inheritance, all handler types support a class-based pattern where you extend `StepHandler` and implement `call(context)`. See [Class-Based Handlers](../reference/class-based-handlers.md) for the full reference.

## See It in Action

The [example apps](../getting-started/example-apps.md) implement step handlers for four real-world workflows in all four languages. Compare the same handler across Rails, FastAPI, Bun, and Axum to see how each framework's idioms map to the Tasker contract.

## Next Steps

- [Your First Workflow](first-workflow.md) — Connect handlers into a multi-step DAG
- Language guides: [Ruby](ruby.md) | [Python](python.md) | [TypeScript](typescript.md) | [Rust](rust.md)
