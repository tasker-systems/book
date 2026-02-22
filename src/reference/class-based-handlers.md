# Class-Based Handlers

The class-based pattern is fully supported and will continue to work in all future versions. For new projects, we recommend the [DSL approach](../building/first-handler.md) — it produces shorter handlers with typed signatures that make the data flow explicit. This page documents the class-based alternative.

## When to Use Class-Based Handlers

- **Existing codebases** with class hierarchies that benefit from inheritance
- **Complex handler lifecycle** requirements (custom initialization, shared state across calls)
- **API handlers** that need the `APIMixin` HTTP client methods
- **Batchable handlers** with complex aggregation logic

## Step Handler

The base handler type. All other types extend it.

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
        prev_result = context.get_dependency_result("previous_step_name")

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

Rust uses the `RustStepHandler` trait directly — this is Rust's only handler pattern (no DSL equivalent, by design).

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

## Context Access Patterns

| Concept | Python | Ruby | TypeScript | Rust |
|---------|--------|------|------------|------|
| Input data | `context.input_data` | `context.input_data` | `context.inputData` | `step_data.task.context` |
| Dependency result | `context.get_dependency_result("step")` | `context.get_dependency_result('step')` | `context.getDependencyResult('step')` | `step_data.dependency_results` |
| Success | `StepHandlerResult.success(result=data)` | `success(result: data)` | `this.success(data)` | `Ok(success_result(...))` |
| Failure | `StepHandlerResult.failure(...)` | `failure(message:, ...)` | `this.failure(msg, type, retryable)` | `Ok(error_result(...))` |

## API Handler

The `APIMixin` adds HTTP client methods with built-in error classification. It provides `self.get()`, `self.post()`, `self.put()`, `self.patch()`, `self.delete()` methods that return an `ApiResponse` wrapper, plus `self.api_success()` and `self.api_failure()` helpers that automatically classify HTTP errors as retryable or permanent.

**When to use**: Calling external APIs where you need to distinguish retryable errors (5xx, timeouts) from permanent errors (4xx).

```python
import httpx

from tasker_core.step_handler import StepHandler
from tasker_core.step_handler.mixins import APIMixin


class FetchOrderHandler(APIMixin, StepHandler):
    handler_name = "fetch_order"
    base_url = "https://api.example.com"
    default_timeout = 30.0

    def call(self, context):
        order_id = context.input_data["order_id"]

        try:
            response = self.get(f"/orders/{order_id}")
        except httpx.ConnectError as e:
            return self.connection_error(e, "fetching order")
        except httpx.TimeoutException as e:
            return self.timeout_error(e, "fetching order")

        if response.ok:
            return self.api_success(response)
        return self.api_failure(response)
```

The `APIMixin` provides:

| Method | Purpose |
|--------|---------|
| `self.get()`, `self.post()`, etc. | HTTP methods returning `ApiResponse` |
| `self.api_success(response)` | Success result with response metadata |
| `self.api_failure(response)` | Failure with automatic error classification (4xx = permanent, 5xx/429 = retryable) |
| `self.connection_error(exc)` | Retryable failure for connection errors |
| `self.timeout_error(exc)` | Retryable failure for timeouts |

Ruby and TypeScript provide equivalent API handler mixins with the same error classification pattern.

## Decision Handler

The `DecisionMixin` adds workflow routing methods. `self.decision_success()` activates downstream steps; `self.skip_branches()` when no steps should execute.

**When to use**: Conditional branching — when the next steps depend on runtime data.

```python
from tasker_core.step_handler import StepHandler
from tasker_core.step_handler.mixins import DecisionMixin


class OrderRoutingHandler(DecisionMixin, StepHandler):
    handler_name = "order_routing"

    def call(self, context):
        order_type = context.input_data.get("order_type")

        if order_type == "premium":
            return self.decision_success(
                ["validate_premium", "process_premium"],
                routing_context={"order_type": order_type},
            )
        elif order_type == "review_required":
            return self.decision_success(
                ["manual_review", "approval_gate"],
                routing_context={"order_type": order_type},
            )
        else:
            return self.decision_success(["standard_processing"])
```

The `DecisionMixin` provides:

| Method | Purpose |
|--------|---------|
| `self.decision_success(steps, routing_context)` | Activate downstream steps by name |
| `self.skip_branches(reason)` | Successful outcome with no follow-up steps |
| `self.decision_failure(message)` | Decision could not be made (usually not retryable) |

See [Conditional Workflows](../guides/conditional-workflows.md) for decision handler patterns in depth.

## Batchable Handler

The `Batchable` mixin adds batch processing methods for splitting large workloads into parallel cursor-based batches.

**When to use**: Processing large datasets where you want to divide work across multiple parallel workers.

**Workflow pattern**:

1. **Analyzer step** — determines total work and creates cursor configs that divide it into batches
2. **Worker steps** — Tasker spawns parallel workers, each processing one batch
3. **Aggregator step** — (optional) combines results from all workers

### Analyzer

```python
from tasker_core.step_handler import StepHandler
from tasker_core.batch_processing import Batchable


class CsvAnalyzerHandler(StepHandler, Batchable):
    handler_name = "analyze_csv"

    def call(self, context):
        total_rows = int(context.input_data.get("total_rows", 10000))

        outcome = self.create_batch_outcome(
            total_items=total_rows,
            batch_size=100,
        )
        return self.batch_analyzer_success(outcome)
```

### Worker

```python
class CsvBatchProcessorHandler(StepHandler, Batchable):
    handler_name = "process_csv_batch"

    def call(self, context):
        batch_context = self.get_batch_worker_context(context)
        cursor = batch_context.cursor

        # Process rows in the assigned range
        rows_processed = cursor.end_cursor - cursor.start_cursor

        return self.batch_worker_success(
            batch_context,
            result={"rows_processed": rows_processed},
        )
```

### Aggregator

```python
from tasker_core.batch_processing import Batchable, BatchAggregationScenario


class CsvResultsAggregatorHandler(StepHandler, Batchable):
    handler_name = "aggregate_csv_results"

    def call(self, context):
        scenario = BatchAggregationScenario.detect(
            context.dependency_results,
            "analyze_csv",
            "process_csv_batch_",
        )

        if scenario.is_no_batches:
            return self.success({"total_rows": 0, "skipped": True})

        total = sum(
            r.get("rows_processed", 0)
            for r in scenario.batch_results.values()
        )
        return self.success({
            "total_rows": total,
            "worker_count": scenario.worker_count,
        })
```

The `Batchable` mixin provides:

| Method | Role | Purpose |
|--------|------|---------|
| `self.create_batch_outcome(total_items, batch_size)` | Analyzer | Create cursor ranges dividing work into batches |
| `self.batch_analyzer_success(outcome)` | Analyzer | Return batch config for worker spawning |
| `self.get_batch_worker_context(context)` | Worker | Extract cursor and batch metadata |
| `self.batch_worker_success(batch_context, result)` | Worker | Return per-batch results |
| `BatchAggregationScenario.detect(...)` | Aggregator | Detect whether batches ran and collect results |

See [Batch Processing](../guides/batch-processing.md) for the full analyzer/worker/aggregator pattern with production examples.

## Registering Class-Based Handlers

Handlers are resolved by matching the `handler.callable` field in task template YAML. The callable format varies by language:

| Language | Format | Example |
|----------|--------|---------|
| Ruby | `Module::ClassName` | `Handlers::ProcessOrderHandler` |
| Python | `module.file.ClassName` | `handlers.process_order_handler.ProcessOrderHandler` |
| TypeScript | `ClassName` | `ProcessOrderHandler` |
| Rust | `function_name` | `process_order` |

See [Handler Resolution](../guides/handler-resolution.md) for the full resolver chain and how callables are matched to handler implementations.
