# Building with Rust

This guide covers building Tasker step handlers with native Rust using the
`tasker-worker-rust` and `tasker-shared` crates in an Axum application.

## Quick Start

Add dependencies to your `Cargo.toml`:

```toml
[dependencies]
tasker-worker-rust = { git = "https://github.com/tasker-systems/tasker-core" }
tasker-shared = { git = "https://github.com/tasker-systems/tasker-core" }
serde_json = "1.0"
serde = { version = "1.0", features = ["derive"] }
```

Generate a step handler with `tasker-ctl`:

```bash
tasker-ctl template generate step_handler \
  --language rust \
  --param name=ValidateCart
```

This creates a handler struct implementing the `RustStepHandler` trait.

## Writing a Step Handler

Rust supports two handler patterns: standalone functions (used in the example apps) and
the `RustStepHandler` trait (used in the generated templates).

### Standalone Function Pattern

The example apps use plain functions that take context as `&Value` and return
`Result<Value, String>`:

```rust
use serde_json::{json, Value};

pub fn validate_cart(context: &Value) -> Result<Value, String> {
    let cart_items: Vec<CartItem> =
        serde_json::from_value(context.get("cart_items").cloned().unwrap_or(json!([])))
            .map_err(|e| format!("Invalid cart_items format: {}", e))?;

    if cart_items.is_empty() {
        return Err("Cart cannot be empty".to_string());
    }

    let mut validated_items = Vec::new();
    let mut subtotal = 0.0_f64;

    for item in &cart_items {
        if item.quantity <= 0 {
            return Err(format!(
                "Invalid quantity {} for product {}",
                item.quantity, item.product_id
            ));
        }

        let line_total = item.price * item.quantity as f64;
        subtotal += line_total;

        validated_items.push(json!({
            "product_id": item.product_id,
            "quantity": item.quantity,
            "unit_price": item.price,
            "line_total": (line_total * 100.0).round() / 100.0
        }));
    }

    let tax = (subtotal * 0.08 * 100.0).round() / 100.0;
    let total = ((subtotal + tax) * 100.0).round() / 100.0;

    Ok(json!({
        "validated_items": validated_items,
        "subtotal": subtotal,
        "tax": tax,
        "total": total,
        "item_count": validated_items.len()
    }))
}
```

### RustStepHandler Trait Pattern

The generated template uses the `RustStepHandler` trait with async support:

```rust
use anyhow::Result;
use async_trait::async_trait;
use serde_json::json;
use std::time::Instant;
use tasker_shared::types::TaskSequenceStep;
use tasker_worker_rust::{success_result, RustStepHandler};
use tasker_worker_rust::step_handlers::StepHandlerConfig;

pub struct ValidateCartHandler {
    config: StepHandlerConfig,
}

#[async_trait]
impl RustStepHandler for ValidateCartHandler {
    fn new(config: StepHandlerConfig) -> Self {
        Self { config }
    }

    fn name(&self) -> &str {
        "ecommerce_validate_cart"
    }

    async fn call(
        &self,
        step_data: &TaskSequenceStep,
    ) -> Result<tasker_shared::messaging::StepExecutionResult> {
        let start = Instant::now();
        let context = &step_data.task.context;

        // Deserialize and validate cart items
        let cart_items = context.get("cart_items")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow::anyhow!("cart_items is required"))?;

        // Business logic...
        let result_data = json!({ "validated": true });
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

## Accessing Task Context

In standalone functions, context is a `&Value` — use serde_json accessors:

```rust
// Read from the task context (standalone function pattern)
let customer_email = context
    .get("customer_email")
    .and_then(|v| v.as_str())
    .unwrap_or("unknown@example.com");

let payment_token = context
    .get("payment_token")
    .and_then(|v| v.as_str())
    .unwrap_or("tok_test_success");

// Deserialize a typed struct from context
let cart_items: Vec<CartItem> =
    serde_json::from_value(context.get("cart_items").cloned().unwrap_or(json!([])))
        .map_err(|e| format!("Invalid cart_items: {}", e))?;
```

In the `RustStepHandler` trait pattern, context lives on `step_data.task.context`:

```rust
let context = &step_data.task.context;
let value = context["field_name"].as_str().unwrap_or("default");
```

## Accessing Dependency Results

Dependency results are passed as a `HashMap<String, Value>` in standalone functions:

```rust
use std::collections::HashMap;

pub fn process_payment(
    context: &Value,
    dependency_results: &HashMap<String, Value>,
) -> Result<Value, String> {
    // Get result from upstream step
    let cart_result = dependency_results
        .get("validate_cart")
        .ok_or("Missing validate_cart dependency result")?;

    let total = cart_result
        .get("total")
        .and_then(|v| v.as_f64())
        .unwrap_or(0.0);

    // Use the upstream data...
    Ok(json!({ "amount_charged": total }))
}
```

## Error Handling

In standalone functions, return `Err(String)` for errors:

```rust
// Validation error (non-retryable)
if cart_items.is_empty() {
    return Err("Cart cannot be empty".to_string());
}

// Business logic error
return Err(format!(
    "Insufficient stock for {}: requested {}, available {}",
    product.name, requested, available
));
```

In the `RustStepHandler` trait pattern, use `error_result` for structured errors:

```rust
use tasker_worker_rust::error_result;

// Non-retryable validation error
Ok(error_result(
    step_data.workflow_step.workflow_step_uuid,
    "Invalid order data".to_string(),
    Some("VALIDATION_ERROR".to_string()),
    Some("ValidationError".to_string()),
    false,  // not retryable
    duration_ms,
    None,
))

// Retryable transient error
Ok(error_result(
    step_data.workflow_step.workflow_step_uuid,
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
  --param handler_callable=ecommerce_order_processing
```

This generates a YAML file defining the workflow. Here is a multi-step example from
the ecommerce example app:

```yaml
name: ecommerce_order_processing
namespace_name: ecommerce_rs
version: 1.0.0
description: "Complete e-commerce order processing workflow"
metadata:
  author: Axum Example Application
  tags:
    - namespace:ecommerce
    - pattern:order_processing
    - language:rust
task_handler:
  callable: ecommerce_order_processing
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
        required: [product_id, quantity]
    customer_email:
      type: string
      format: email
steps:
  - name: validate_cart
    description: "Validate cart items, calculate totals"
    handler:
      callable: ecommerce_validate_cart
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
      callable: ecommerce_process_payment
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
      callable: ecommerce_update_inventory
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
      callable: ecommerce_create_order
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
      callable: ecommerce_send_confirmation
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
- **`steps[].handler.callable`** — Snake-case function name (e.g., `ecommerce_validate_cart`)
- **`steps[].dependencies`** — DAG edges defining execution order
- **`steps[].retry`** — Per-step retry policy with backoff

## Testing

Test standalone handler functions directly:

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
        assert_eq!(result.get("item_count").unwrap().as_i64().unwrap(), 3);
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
            "payment_token": "tok_test_success",
            "payment_method": "credit_card"
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

Test `RustStepHandler` implementations:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use tasker_worker_rust::StepHandlerConfig;

    #[test]
    fn test_handler_name() {
        let config = StepHandlerConfig::new(json!({}));
        let handler = ValidateCartHandler::new(config);
        assert_eq!(handler.name(), "ecommerce_validate_cart");
    }
}
```

## Next Steps

- See the [Quick Start Guide](../guides/quick-start.md) for running the full workflow end-to-end
- See [Architecture](../architecture/index.md) for system design details
- Browse the [Axum example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app) for complete handler implementations
