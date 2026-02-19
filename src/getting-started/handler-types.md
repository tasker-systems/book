# Handler Types

Tasker provides four specialized handler types that cover the most common workflow patterns. Each type is a composable mixin that you combine with the base `StepHandler` via multiple inheritance, adding purpose-built methods so you write business logic instead of boilerplate.

## Cross-Language Availability

| Handler Type | Python | Ruby | TypeScript | Rust |
|---|---|---|---|---|
| **Step Handler** | Yes | Yes | Yes | Yes |
| **API Handler** | Yes | Yes | Yes | -- |
| **Decision Handler** | Yes | Yes | Yes | -- |
| **Batchable Handler** | Yes | Yes | Yes | -- |

Rust provides only the base Step Handler. The specialized types (API, Decision, Batchable) are unnecessary in Rust because the native ecosystem already provides excellent HTTP clients, pattern matching, and iterator-based parallelism. See [Rust intentional omissions](#why-rust-has-only-step-handler) below.

## Step Handler

The base handler type. All other handler types extend it.

**When to use**: General-purpose business logic — database operations, calculations, transformations, service calls, or anything that takes input and produces output.

```python
from tasker_core import StepHandler, StepContext, StepHandlerResult


class ProcessPaymentHandler(StepHandler):
    handler_name = "process_payment"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        # Access input data from the task context
        input_data = context.input_data

        # Access results from upstream dependency steps
        # prev_result = context.get_dependency_result("previous_step_name")

        result = {
            "processed": True,
            "handler": "process_payment",
        }

        return StepHandlerResult.success(result=result)
```

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate step_handler \
  --plugin tasker-contrib-python \
  --param name=ProcessPayment
```

Available for all four languages: `tasker-contrib-rails`, `tasker-contrib-python`, `tasker-contrib-typescript`, `tasker-contrib-rust`.

**See it in action**: All five workflows in the [example apps](../contrib/example-apps.md) use step handlers. Start with the e-commerce checkout ([Post 01](../stories/post-01-ecommerce-checkout.md)) for the simplest example.

**Next**: [Your First Handler](../building/first-handler.md) walks through writing and registering a step handler end-to-end.

## API Handler

A mixin that adds HTTP client methods with built-in error classification. The `APIMixin` provides `self.get()`, `self.post()`, `self.put()`, `self.patch()`, `self.delete()` methods that return an `ApiResponse` wrapper, plus `self.api_success()` and `self.api_failure()` helpers that automatically classify HTTP errors as retryable or permanent.

**When to use**: Calling external APIs where you need to distinguish retryable errors (5xx, timeouts) from permanent errors (4xx). The mixin handles error classification so the orchestrator knows whether to retry.

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

The `ApiResponse` wrapper exposes `.ok`, `.is_retryable`, `.is_client_error`, `.is_server_error`, and `.retry_after` for fine-grained control when you need it.

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate step_handler_api \
  --plugin tasker-contrib-python \
  --param name=FetchOrder \
  --param base_url=https://api.example.com
```

**Cross-language notes**: Ruby and TypeScript provide equivalent API handler mixins with the same error classification pattern.

## Decision Handler

A mixin that adds workflow routing methods. The `DecisionMixin` provides `self.decision_success()` to activate downstream steps and `self.skip_branches()` when no steps should execute.

**When to use**: Conditional branching — when the next steps depend on runtime data. The decision handler returns a list of step names to activate, enabling dynamic workflow paths without hardcoding logic into the DAG definition.

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

Key differences from a regular step handler:

- Composes `DecisionMixin` with `StepHandler` via multiple inheritance
- Returns `self.decision_success(["step_name", ...])` with step names to activate
- The `routing_context` is stored as part of the step result for downstream access

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate step_handler_decision \
  --plugin tasker-contrib-python \
  --param name=OrderRouting
```

**Learn more**: [Conditional Workflows](../guides/conditional-workflows.md) covers decision handler patterns in depth, including multi-level routing and fallback strategies.

## Batchable Handler

A mixin that adds batch processing methods for splitting large workloads into parallel cursor-based batches. The `Batchable` mixin provides `self.create_batch_outcome()` and `self.batch_analyzer_success()` for the analyzer role, plus batch worker context helpers and aggregation utilities.

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

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate step_handler_batchable \
  --plugin tasker-contrib-python \
  --param name=DataExport
```

**Learn more**: [Batch Processing](../guides/batch-processing.md) covers the full analyzer/worker/aggregator pattern with production examples.

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

## Why Rust Has Only Step Handler

Rust's standard library and ecosystem already provide the patterns that the specialized handler types encapsulate:

- **API calls**: `reqwest` or `hyper` with Rust's `Result` type for error classification
- **Decision routing**: `match` expressions with exhaustiveness checking
- **Batch processing**: `rayon` for data parallelism, iterators with `.chunks()` for batching

The specialized handler types exist to give Python, Ruby, and TypeScript developers a structured pattern for these common operations. Rust developers get that structure from the language itself.
