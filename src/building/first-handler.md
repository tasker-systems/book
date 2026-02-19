# Your First Handler

This guide walks you through writing your first step handler.

## What is a Handler?

A **Step Handler** is a class (or function, in Rust) that executes business logic for a single workflow step. Handlers:

- Receive a **StepContext** with input data, dependency results, and configuration
- Perform operations (API calls, database queries, calculations)
- Return a **success** or **failure** result for downstream steps

You can generate a handler from a template with `tasker-ctl`:

```bash
tasker-ctl template generate step_handler --language python --param name=ProcessOrder
```

Or write one from scratch using the patterns below.

## Handler Anatomy by Language

### Python

```python
from tasker_core import StepContext, StepHandler, StepHandlerResult


class ProcessOrderHandler(StepHandler):
    handler_name = "process_order"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        # Access input data from the task context
        input_data = context.input_data

        # Access results from upstream dependency steps
        # prev_result = context.get_dependency_result("previous_step_name")

        result = {
            "processed": True,
            "handler": "process_order",
        }

        return StepHandlerResult.success(result=result)
```

### Ruby

```ruby
require 'tasker_core'

module Handlers
  class ProcessOrderHandler < TaskerCore::StepHandler::Base
    def call(context)
      # Access input data from the task context
      input = context.input_data

      # Access results from upstream dependency steps
      # prev_result = context.get_dependency_result('previous_step_name')

      result = {
        processed: true,
        handler: 'process_order'
      }

      success(result: result)
    rescue StandardError => e
      failure(
        message: e.message,
        error_type: 'RetryableError',
        retryable: true,
        metadata: { handler: 'process_order' }
      )
    end
  end
end
```

### TypeScript

```typescript
import {
  StepHandler,
  type StepContext,
  type StepHandlerResult,
  ErrorType,
} from '@tasker-systems/tasker';

export class ProcessOrderHandler extends StepHandler {
  static handlerName = 'process_order';
  static handlerVersion = '1.0.0';

  async call(context: StepContext): Promise<StepHandlerResult> {
    try {
      // Access input data from the task context
      const inputData = context.inputData;

      // Access results from upstream dependency steps
      // const prevResult = context.getDependencyResult('previous_step_name');

      const result = {
        processed: true,
        handler: 'process_order',
      };

      return this.success(result);
    } catch (error) {
      return this.failure(
        error instanceof Error ? error.message : String(error),
        ErrorType.RETRYABLE_ERROR,
        true,
      );
    }
  }
}
```

### Rust

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

        // Access input data from the task context
        let _input_data = &step_data.task.context;

        // Access dependency results from upstream steps
        // let _dep_results = &step_data.dependency_results;

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

## Key Patterns

| Concept | Python | Ruby | TypeScript | Rust |
|---------|--------|------|------------|------|
| Input data | `context.input_data` | `context.input_data` | `context.inputData` | `step_data.task.context` |
| Dependency result | `context.get_dependency_result("step")` | `context.get_dependency_result('step')` | `context.getDependencyResult('step')` | `step_data.dependency_results` |
| Success | `StepHandlerResult.success(result=data)` | `success(result: data)` | `this.success(data)` | `Ok(success_result(...))` |
| Failure | `StepHandlerResult.failure(...)` | `failure(message:, ...)` | `this.failure(msg, type, retryable)` | `Ok(error_result(...))` |

## Registering Handlers

Handlers are resolved by matching the `handler.callable` field in task template YAML. The callable format varies by language:

| Language | Format | Example |
|----------|--------|---------|
| Ruby | `Module::ClassName` | `Handlers::ProcessOrderHandler` |
| Python | `module.file.ClassName` | `handlers.process_order_handler.ProcessOrderHandler` |
| TypeScript | `ClassName` | `ProcessOrderHandler` |
| Rust | `function_name` | `process_order` |

## See It in Action

The [example apps](../getting-started/example-apps.md) implement step handlers for four real-world workflows in all four languages. Compare the same handler across Rails, FastAPI, Bun, and Axum to see how each framework's idioms map to the Tasker contract.

## Next Steps

- [Your First Workflow](first-workflow.md) — Connect handlers into a multi-step DAG
- Language guides: [Ruby](ruby.md) | [Python](python.md) | [TypeScript](typescript.md) | [Rust](rust.md)
