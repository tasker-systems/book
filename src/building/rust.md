# Rust Guide

This guide covers using Tasker with native Rust step handlers.

## Quick Start

```bash
# Add dependencies to Cargo.toml
[dependencies]
tasker-worker-rust = { git = "https://github.com/tasker-systems/tasker-core" }
tasker-shared = { git = "https://github.com/tasker-systems/tasker-core" }
async-trait = "0.1"
serde_json = "1.0"
anyhow = "1.0"
```

## Writing a Step Handler

Rust step handlers implement the `RustStepHandler` trait using `async_trait`:

```rust path=null start=null
use anyhow::Result;
use async_trait::async_trait;
use tasker_shared::types::TaskSequenceStep;
use tasker_shared::messaging::StepExecutionResult;
use tasker_worker_rust::RustStepHandler;
use tasker_worker_rust::step_handlers::StepHandlerConfig;

#[async_trait]
pub trait RustStepHandler: Send + Sync {
    fn new(config: StepHandlerConfig) -> Self;
    fn name(&self) -> &str;
    async fn call(
        &self,
        step_data: &TaskSequenceStep,
    ) -> Result<StepExecutionResult>;
}
```

### Minimal Handler Example

```rust path=null start=null
use anyhow::Result;
use async_trait::async_trait;
use serde_json::json;
use std::time::Instant;
use tasker_shared::messaging::StepExecutionResult;
use tasker_shared::types::TaskSequenceStep;
use tasker_worker_rust::success_result;
use tasker_worker_rust::step_handlers::StepHandlerConfig;
use tasker_worker_rust::RustStepHandler;

pub struct MyHandler {
    config: StepHandlerConfig,
}

#[async_trait]
impl RustStepHandler for MyHandler {
    fn new(config: StepHandlerConfig) -> Self {
        Self { config }
    }

    fn name(&self) -> &str {
        "my_handler"
    }

    async fn call(
        &self,
        step_data: &TaskSequenceStep,
    ) -> Result<StepExecutionResult> {
        let start = Instant::now();

        // Access task context data
        let _input_data = &step_data.task.context;

        // Perform your business logic
        let result_data = json!({ "result": "processed" });

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

### Accessing Task Context

Use `get_input()` for type-safe task context access:

```rust path=null start=null
// Get required value (returns Error if missing)
let customer_id: i64 = step_data.get_input("customer_id")?;

// Get optional value with default
let timeout: i64 = step_data.get_input_or("timeout_ms", 5000);
```

### Accessing Dependency Results

Access results from upstream steps using `get_dependency_result_column_value()`:

```rust path=null start=null
// Get result from a specific upstream step
let previous_result: i64 = step_data
    .get_dependency_result_column_value("previous_step_name")?;

// Handle complex JSON results
let order_data: serde_json::Value = step_data
    .get_dependency_result_column_value("validate_order")?;
let total = order_data["order_total"].as_f64().unwrap_or(0.0);
```

## Complete Example: Order Validation Handler

This example shows a real-world handler with validation and error handling:

```rust path=null start=null
use anyhow::Result;
use async_trait::async_trait;
use serde_json::json;
use std::time::Instant;
use tasker_shared::messaging::StepExecutionResult;
use tasker_shared::types::TaskSequenceStep;
use tasker_worker_rust::{error_result, success_result, RustStepHandler};
use tasker_worker_rust::step_handlers::StepHandlerConfig;

pub struct ValidateOrderHandler {
    config: StepHandlerConfig,
}

#[async_trait]
impl RustStepHandler for ValidateOrderHandler {
    fn new(config: StepHandlerConfig) -> Self {
        Self { config }
    }

    fn name(&self) -> &str {
        "validate_order"
    }

    async fn call(
        &self,
        step_data: &TaskSequenceStep,
    ) -> Result<StepExecutionResult> {
        let start = Instant::now();

        // Access task context
        let context = &step_data.task.context;
        let customer = &context["customer"];
        let customer_id = customer["id"].as_i64()
            .ok_or_else(|| anyhow::anyhow!("Customer ID is required"))?;

        // Extract and validate order items
        let items = context["items"].as_array()
            .ok_or_else(|| anyhow::anyhow!("Items array is required"))?;

        if items.is_empty() {
            let duration_ms = start.elapsed().as_millis() as i64;
            return Ok(error_result(
                step_data.workflow_step.workflow_step_uuid,
                "Order items cannot be empty".to_string(),
                Some("EMPTY_ORDER".to_string()),       // error_code
                Some("ValidationError".to_string()),    // error_type
                false,                                   // retryable
                duration_ms,
                None,                                    // context metadata
            ));
        }

        // Calculate order total
        let total: f64 = items.iter()
            .map(|item| {
                let price = item["price"].as_f64().unwrap_or(0.0);
                let qty = item["quantity"].as_i64().unwrap_or(0) as f64;
                price * qty
            })
            .sum();

        let duration_ms = start.elapsed().as_millis() as i64;

        Ok(success_result(
            step_data.workflow_step.workflow_step_uuid,
            json!({
                "customer_id": customer_id,
                "validated_items": items,
                "order_total": total,
                "validation_status": "complete",
            }),
            duration_ms,
            None,
        ))
    }
}
```

## Handler Registry

Register handlers so the worker can discover them:

```rust path=null start=null
use std::collections::HashMap;
use std::sync::Arc;

pub struct RustStepHandlerRegistry {
    handlers: HashMap<String, Box<dyn Fn() -> Box<dyn RustStepHandler>>>,
}

impl RustStepHandlerRegistry {
    pub fn new() -> Self {
        let mut registry = Self {
            handlers: HashMap::new(),
        };

        // Register handlers
        registry.register("validate_order", || Box::new(ValidateOrderHandler));
        registry.register("process_payment", || Box::new(ProcessPaymentHandler));

        registry
    }

    pub fn register<F>(&mut self, name: &str, factory: F)
    where
        F: Fn() -> Box<dyn RustStepHandler> + 'static,
    {
        self.handlers.insert(name.to_string(), Box::new(factory));
    }

    pub fn get_handler(&self, name: &str) -> Option<Box<dyn RustStepHandler>> {
        self.handlers.get(name).map(|f| f())
    }
}
```

## Task Template Configuration

Define workflows in YAML:

```yaml path=null start=null
name: order_fulfillment
namespace_name: ecommerce
version: "1.0.0"
description: "E-commerce order processing workflow"

steps:
  - name: validate_order
    description: "Validate order data"
    handler:
      callable: validate_order
      initialization: {}
    dependencies: []
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: reserve_inventory
    description: "Reserve items in warehouse"
    handler:
      callable: reserve_inventory
      initialization: {}
    dependencies:
      - validate_order
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: process_payment
    description: "Charge customer"
    handler:
      callable: process_payment
      initialization: {}
    dependencies:
      - reserve_inventory
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: ship_order
    description: "Ship the order"
    handler:
      callable: ship_order
      initialization: {}
    dependencies:
      - process_payment
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000
```

## Running the Worker

Bootstrap and run a native Rust worker:

```rust path=null start=null
use tasker_worker::WorkerBootstrap;
use std::sync::Arc;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Initialize handler registry
    let registry = Arc::new(RustStepHandlerRegistry::new());

    // Create event handler
    let event_system = get_global_event_system();
    let event_handler = RustEventHandler::new(
        registry,
        event_system.clone(),
        "rust-worker-1".to_string(),
    );

    // Start event handler
    event_handler.start().await?;

    // Bootstrap worker
    let config = WorkerBootstrapConfig {
        namespace: "order_fulfillment".to_string(),
        ..Default::default()
    };

    let worker_handle = WorkerBootstrap::bootstrap_with_event_system(
        config,
        Some(event_system),
    ).await?;

    // Wait for shutdown signal
    worker_handle.wait_for_shutdown().await?;

    Ok(())
}
```

## Testing

Write integration tests with real database interactions:

```rust path=null start=null
#[tokio::test]
async fn test_validate_order_handler() {
    let handler = ValidateOrderHandler;

    // Create mock step data
    let step_data = create_test_step_data(json!({
        "customer": {"id": 123, "email": "test@example.com"},
        "items": [
            {"product_id": 1, "quantity": 2, "price": 29.99}
        ]
    }));

    let result = handler.call(&step_data).await.unwrap();

    assert!(result.success);
    assert_eq!(result.result["order_total"], 59.98);
}
```

Run tests:

```bash
cargo test --test integration
```

## Error Handling

Return structured errors using the `error_result` helper:

```rust path=null start=null
use tasker_worker_rust::error_result;

// Non-retryable validation error
Ok(error_result(
    step_data.workflow_step.workflow_step_uuid,
    "Invalid order data".to_string(),
    Some("VALIDATION_ERROR".to_string()),   // error_code
    Some("ValidationError".to_string()),     // error_type
    false,                                    // retryable
    duration_ms,
    None,                                     // context metadata
))

// Retryable transient error
Ok(error_result(
    step_data.workflow_step.workflow_step_uuid,
    "Payment gateway timeout".to_string(),
    Some("GATEWAY_TIMEOUT".to_string()),
    Some("NetworkError".to_string()),
    true,                                     // retryable
    duration_ms,
    Some(metadata),                           // HashMap<String, Value>
))

// Or use anyhow for unrecoverable errors
Err(anyhow::anyhow!("Fatal system error"))
```

## Common Patterns

### Context Access

```rust path=null start=null
// Access task context directly
let context = &step_data.task.context;
let value = context["field_name"].as_str().unwrap_or("default");

// Access nested values
let items = context["items"].as_array();
```

### Dependency Result Access

```rust path=null start=null
// Access dependency results from upstream steps
let dep_results = &step_data.dependency_results;
```

## Submitting Tasks via Client SDK

Rust applications can submit tasks directly using `tasker-client`:

```rust path=null start=null
use tasker_client::{OrchestrationApiClient, OrchestrationApiConfig};
use tasker_shared::models::core::task_request::TaskRequest;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    // Create client
    let config = OrchestrationApiConfig::default();
    let client = OrchestrationApiClient::new(config)?;

    // Create a task
    let task_request = TaskRequest {
        name: "order_fulfillment".to_string(),
        namespace: "ecommerce".to_string(),
        version: "1.0.0".to_string(),
        context: serde_json::json!({
            "customer": {"id": 123, "email": "customer@example.com"},
            "items": [
                {"product_id": 1, "quantity": 2, "price": 29.99}
            ]
        }),
        initiator: "my-service".to_string(),
        source_system: "api".to_string(),
        reason: "New order received".to_string(),
        ..Default::default()
    };

    let response = client.create_task(task_request).await?;
    println!("Task created: {}", response.task_uuid);

    // Get task status
    let task = client.get_task(response.task_uuid).await?;
    println!("Task status: {}", task.status);

    // List task steps
    let steps = client.list_task_steps(response.task_uuid).await?;
    for step in steps {
        println!("Step {}: {}", step.name, step.current_state);
    }

    Ok(())
}
```

### Configuration

Configure via environment variables or TOML config:

```bash
export ORCHESTRATION_URL=http://localhost:8080
export ORCHESTRATION_API_KEY=your-api-key
```

Or create `.config/tasker-client.toml`:

```toml path=null start=null
[profiles.local]
transport = "rest"
orchestration_url = "http://localhost:8080"

[profiles.production]
transport = "grpc"
orchestration_url = "https://tasker.example.com:9190"
api_key = "your-production-key"
```

## Next Steps

- See [Architecture](../architecture/README.md) for system design
- See [Workers Reference](../workers/README.md) for advanced patterns
- See the [tasker-core workers/rust](https://github.com/tasker-systems/tasker-core/tree/main/workers/rust) for complete examples
