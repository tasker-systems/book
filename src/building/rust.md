# Building with Rust

This guide covers building Tasker step handlers with native Rust using the
`tasker-worker` and `tasker-shared` crates in an Axum application.

## Quick Start

Add dependencies to your `Cargo.toml`:

```toml
[dependencies]
tasker-worker = "0.1"
tasker-shared = "0.1"
tasker-client = "0.1"
serde = { version = "1", features = ["derive"] }
serde_json = "1"
async-trait = "0.1"
```

Generate a step handler with `tasker-ctl`:

```bash
tasker-ctl template generate step_handler \
  --language rust \
  --param name=ValidateCart
```

This creates a handler implementing the `StepHandler` trait.

> **No DSL equivalent**: Rust uses the `StepHandler` trait directly — the trait IS the pattern. Python, Ruby, and TypeScript have DSL wrappers for ergonomics, but Rust's trait system provides the same structure natively. For the DSL approach in other languages, see [Python](python.md), [Ruby](ruby.md), or [TypeScript](typescript.md).

## Writing a Step Handler

The [Axum example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app) uses plain functions wrapped in a handler registry. This is the recommended pattern for Rust handlers — write business logic as standalone functions, then register them with the worker.

### Standalone Functions

Each handler function takes the task context and/or dependency results and returns `Result<Value, String>`:

```rust
use serde_json::{json, Value};
use std::collections::HashMap;

/// Step 1: Validate cart items, calculate totals.
/// No dependencies — receives task context only.
pub fn validate_cart(context: &Value) -> Result<Value, String> {
    let cart_items: Vec<CartItem> =
        serde_json::from_value(context.get("cart_items").cloned().unwrap_or(json!([])))
            .map_err(|e| format!("Invalid cart_items format: {}", e))?;

    if cart_items.is_empty() {
        return Err("Cart cannot be empty".to_string());
    }

    // Business logic: validate items, calculate pricing...
    let mut subtotal = 0.0_f64;
    for item in &cart_items {
        subtotal += item.price * item.quantity as f64;
    }
    let tax = (subtotal * 0.08 * 100.0).round() / 100.0;
    let total = ((subtotal + tax) * 100.0).round() / 100.0;

    Ok(json!({
        "validated_items": cart_items,
        "subtotal": subtotal,
        "tax": tax,
        "total": total,
        "item_count": cart_items.len()
    }))
}
```

### Functions with Dependencies

Handlers that need upstream step results receive a `HashMap<String, Value>`:

```rust
/// Step 2: Process payment using cart total from validate_cart.
pub fn process_payment(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let token = context
        .get("payment_token")
        .and_then(|v| v.as_str())
        .unwrap_or("tok_test_success");

    let cart_result = dependency_results
        .get("validate_cart")
        .ok_or("Missing validate_cart dependency result")?;
    let cart_total = cart_result
        .get("total")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);

    // Business logic: process payment...
    Ok(json!({
        "transaction_id": format!("txn_{}", uuid::Uuid::new_v4()),
        "amount_charged": cart_total,
        "status": "completed"
    }))
}
```

Some handlers only need dependency results (no task context):

```rust
/// Step 3: Reserve inventory based on validated cart items.
pub fn update_inventory(
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    let cart_result = dependency_results
        .get("validate_cart")
        .ok_or("Missing validate_cart dependency result")?;

    let validated_items = cart_result
        .get("validated_items")
        .and_then(|v| v.as_array())
        .ok_or("Missing validated_items in cart result")?;

    // Business logic: create inventory reservations...
    Ok(json!({
        "total_items_reserved": validated_items.len(),
        "status": "reserved"
    }))
}
```

## Handler Registry

Plain functions are bridged to the `StepHandler` trait via a `FunctionHandler` wrapper and registered in a `StepHandlerRegistry`. The registry matches the `handler.callable` field from task template YAML:

```rust
use std::sync::{Arc, RwLock};
use std::collections::HashMap;
use async_trait::async_trait;
use tasker_worker::worker::handlers::{StepHandler, StepHandlerRegistry};
use tasker_shared::types::base::TaskSequenceStep;
use tasker_shared::messaging::StepExecutionResult;

pub struct AxumHandlerRegistry {
    handlers: RwLock<HashMap<String, Arc<dyn StepHandler>>>,
}

impl AxumHandlerRegistry {
    pub fn new() -> Self {
        let registry = Self { handlers: RwLock::new(HashMap::new()) };
        // Register all handlers — callable names match YAML handler.callable
        registry.register_fn("ecommerce_validate_cart",
            Box::new(|ctx, _deps| handlers::ecommerce::validate_cart(ctx)));
        registry.register_fn("ecommerce_process_payment",
            Box::new(|ctx, deps| handlers::ecommerce::process_payment(ctx, deps)));
        // ... more handlers
        registry
    }
}
```

The `FunctionHandler` wrapper extracts context and dependency results from the `TaskSequenceStep` and calls the plain function:

```rust
#[async_trait]
impl StepHandler for FunctionHandler {
    async fn call(&self, step: &TaskSequenceStep) -> TaskerResult<StepExecutionResult> {
        let context = step.task.task.context.clone()
            .unwrap_or_else(|| Value::Object(Default::default()));
        let dep_results: HashMap<String, Value> = step.dependency_results
            .iter()
            .map(|(name, result)| (name.clone(), result.result.clone()))
            .collect();

        match (self.handler_fn)(&context, &dep_results) {
            Ok(result) => Ok(StepExecutionResult::success(
                step.workflow_step.workflow_step_uuid,
                result, elapsed_ms, None,
            )),
            Err(err) => Ok(StepExecutionResult::failure(
                step.workflow_step.workflow_step_uuid,
                err, None, None, false, elapsed_ms, None,
            )),
        }
    }
}
```

## Accessing Task Context

In standalone functions, context is a `&Value` — use serde\_json accessors:

```rust
// Read a string field with a default
let customer_email = context
    .get("customer_email")
    .and_then(|v| v.as_str())
    .unwrap_or("unknown@example.com");

// Deserialize into a typed struct
#[derive(Debug, Deserialize)]
struct CartItem {
    product_id: i64,
    quantity: i64,
}

let cart_items: Vec<CartItem> =
    serde_json::from_value(context.get("cart_items").cloned().unwrap_or(json!([])))
        .map_err(|e| format!("Invalid cart_items: {}", e))?;
```

## Accessing Dependency Results

Dependency results are a `HashMap<String, Value>` mapping step names to their result JSON:

```rust
// Get a single upstream result
let cart_result = dependency_results
    .get("validate_cart")
    .ok_or("Missing validate_cart dependency")?;
let total = cart_result.get("total").and_then(|v| v.as_f64()).unwrap_or(0.0);

// Combine results from multiple upstream steps (convergence)
let payment_result = dependency_results
    .get("process_payment")
    .ok_or("Missing process_payment dependency")?;
let inventory_result = dependency_results
    .get("update_inventory")
    .ok_or("Missing update_inventory dependency")?;
```

## Error Handling

Return `Err(String)` from standalone functions. The `FunctionHandler` wrapper converts errors to `StepExecutionResult::failure`:

```rust
// Validation error (permanent — will not retry)
if cart_items.is_empty() {
    return Err("Cart cannot be empty".to_string());
}

// Business logic error with context
return Err(format!(
    "Insufficient stock for {}: requested {}, available {}",
    product.name, requested, available
));
```

For finer control over retryability, use `StepExecutionResult` directly in a `StepHandler` implementation:

```rust
// Non-retryable error
Ok(StepExecutionResult::failure(
    step.workflow_step.workflow_step_uuid,
    "Invalid order data".to_string(),
    Some("VALIDATION_ERROR".to_string()),
    Some("ValidationError".to_string()),
    false,  // not retryable
    duration_ms,
    None,
))

// Retryable transient error
Ok(StepExecutionResult::failure(
    step.workflow_step.workflow_step_uuid,
    "Payment gateway unreachable".to_string(),
    Some("GATEWAY_ERROR".to_string()),
    Some("NetworkError".to_string()),
    true,  // retryable
    duration_ms,
    None,
))
```

## Task Template Configuration

Generate a task template with `tasker-ctl`:

```bash
tasker-ctl template generate task_template \
  --language rust \
  --param name=EcommerceOrderProcessing \
  --param namespace=ecommerce \
  --param handler_callable=ecommerce_validate_cart
```

Rust handler callables use the snake\_case names registered in the handler registry (e.g., `ecommerce_validate_cart`, `ecommerce_process_payment`).

## Testing

Test standalone handler functions directly with serde\_json values:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::collections::HashMap;

    #[test]
    fn test_validate_cart_success() {
        let context = json!({
            "cart_items": [
                {"product_id": 1, "quantity": 2},
                {"product_id": 2, "quantity": 1}
            ]
        });

        let result = validate_cart(&context).unwrap();

        assert!(result.get("total").unwrap().as_f64().unwrap() > 0.0);
    }

    #[test]
    fn test_validate_cart_empty() {
        let context = json!({"cart_items": []});

        let result = validate_cart(&context);

        assert!(result.is_err());
        assert!(result.unwrap_err().contains("empty"));
    }

    #[test]
    fn test_process_payment_with_dependency() {
        let context = json!({
            "payment_token": "tok_test_success"
        });

        let mut deps = HashMap::new();
        deps.insert("validate_cart".to_string(), json!({
            "total": 64.79,
            "validated_items": []
        }));

        let result = process_payment(&context, &deps).unwrap();

        assert_eq!(result["status"], "completed");
        assert_eq!(result["amount_charged"], 64.79);
    }
}
```

## Capability Traits

Beyond the base `StepHandler`, the worker crate defines capability traits in `handler_capabilities.rs` for specialized patterns:

| Trait | What it provides |
|---|---|
| `APICapable` | HTTP client methods with retryable/permanent error classification |
| `DecisionCapable` | Workflow routing via step activation |
| `BatchableCapable` | Cursor-based parallel batch processing |

A Rust handler implements `StepHandler` and adds any capability traits it needs — this is idiomatic Rust trait composition. For a complex example combining multiple capabilities, see `diamond_decision_batch.rs` in the Rust worker crate.

The Rust `batch_processing` module is the **foundation** that Python, Ruby, and TypeScript access through FFI. The specialized handler types in those languages are ergonomic wrappers — Rust developers work with the underlying traits directly.

## Next Steps

- [Your First Workflow](first-workflow.md) — Build a multi-step DAG end-to-end
- [Architecture](../architecture/index.md) — System design details
- [Axum example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app) — Complete working implementation
