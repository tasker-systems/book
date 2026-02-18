# Handler Types

Tasker provides four specialized handler types that cover the most common workflow patterns. Each handler type extends the base `StepHandler` with purpose-built behavior, so you write business logic instead of boilerplate.

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

**Next**: [Your First Handler](first-handler.md) walks through writing and registering a step handler end-to-end.

## API Handler

An async handler designed for HTTP service calls with built-in error classification.

**When to use**: Calling external APIs where you need to distinguish retryable errors (5xx, timeouts) from permanent errors (4xx). The handler pattern provides structured error handling so the orchestrator knows whether to retry.

```python
import httpx

from tasker_core import StepHandler, StepContext, StepHandlerResult, ErrorType


class FetchOrderHandler(StepHandler):
    handler_name = "fetch_order"
    handler_version = "1.0.0"

    async def call(self, context: StepContext) -> StepHandlerResult:
        base_url = context.step_config.get("base_url", "https://api.example.com")
        endpoint = context.input_data.get("endpoint", "/resource")
        url = f"{base_url}{endpoint}"

        try:
            async with httpx.AsyncClient() as client:
                response = await client.get(url)

            if response.is_success:
                return StepHandlerResult.success(
                    result=response.json(),
                    metadata={
                        "status_code": response.status_code,
                        "endpoint": endpoint,
                    },
                )
            else:
                retryable = response.status_code >= 500
                return StepHandlerResult.failure(
                    message=f"API request failed: HTTP {response.status_code}",
                    error_type=(
                        ErrorType.RETRYABLE_ERROR if retryable
                        else ErrorType.PERMANENT_ERROR
                    ),
                    retryable=retryable,
                    metadata={
                        "status_code": response.status_code,
                        "endpoint": endpoint,
                    },
                )

        except httpx.TimeoutException as exc:
            return StepHandlerResult.failure(
                message=f"API timeout: {exc}",
                error_type=ErrorType.TIMEOUT,
                retryable=True,
            )
        except httpx.ConnectError as exc:
            return StepHandlerResult.failure(
                message=f"API connection failed: {exc}",
                error_type=ErrorType.RETRYABLE_ERROR,
                retryable=True,
            )
```

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate step_handler_api \
  --plugin tasker-contrib-python \
  --param name=FetchOrder \
  --param base_url=https://api.example.com
```

**Cross-language notes**: Ruby and TypeScript API handlers follow the same error classification pattern. Ruby uses `Faraday`, TypeScript uses the built-in `fetch` API.

## Decision Handler

A handler that routes the workflow by selecting which downstream steps should execute.

**When to use**: Conditional branching — when the next steps depend on runtime data. The decision handler returns a list of step names to activate, enabling dynamic workflow paths without hardcoding logic into the DAG definition.

```python
from tasker_core import DecisionHandler, StepContext, StepHandlerResult


class OrderRoutingHandler(DecisionHandler):
    handler_name = "order_routing"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        input_data = context.input_data
        route_key = input_data.get("route_key", "default")

        if route_key == "fast_track":
            return self.decision_success(
                steps=["fast_track_processing"],
                result_data={
                    "route": "fast_track",
                    "reason": "Meets fast-track criteria",
                },
            )
        elif route_key == "review_required":
            return self.decision_success(
                steps=["manual_review", "approval_gate"],
                result_data={
                    "route": "review",
                    "reason": "Review required",
                },
            )
        else:
            return self.decision_success(
                steps=["standard_processing"],
                result_data={
                    "route": "standard",
                    "reason": "Default routing",
                },
            )
```

Key differences from a regular step handler:

- Extends `DecisionHandler` instead of `StepHandler`
- Returns `self.decision_success(steps=[...])` with a list of step names to activate
- The `result_data` is stored as the step result for downstream access

**Generate with tasker-ctl**:

```bash
tasker-ctl template generate step_handler_decision \
  --plugin tasker-contrib-python \
  --param name=OrderRouting
```

**Learn more**: [Conditional Workflows](../guides/conditional-workflows.md) covers decision handler patterns in depth, including multi-level routing and fallback strategies.

## Batchable Handler

A handler that splits large workloads into parallel batches using a cursor-based pagination pattern.

**When to use**: Processing large datasets where you want to divide work across multiple parallel workers. The batchable handler acts as both an **analyzer** (dividing work into cursor ranges) and a **worker** (processing individual batches).

**Workflow pattern**:

1. **Analyzer step** — determines total work and creates cursor configs that divide it into batches
2. **Worker steps** — Tasker spawns parallel workers, each processing one batch
3. **Aggregator step** — (optional) combines results from all workers

```python
from datetime import datetime, timezone

from tasker_core import StepHandler, StepContext, StepHandlerResult


class DataExportHandler(StepHandler):
    handler_name = "data_export"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        # Check if this is a batch worker invocation
        batch_inputs = context.step_inputs or {}
        if batch_inputs.get("cursor") or batch_inputs.get("is_no_op"):
            return self._process_batch(context, batch_inputs)

        # Otherwise, this is the analyzer
        return self._analyze_and_create_batches(context)

    def _analyze_and_create_batches(
        self, context: StepContext
    ) -> StepHandlerResult:
        total_items = int(context.input_data.get("total_items", 1000))
        worker_count = int(context.step_config.get("worker_count", 5))

        items_per_worker = -(-total_items // worker_count)  # ceiling division
        cursor_configs = []
        for i in range(worker_count):
            start = i * items_per_worker
            end = min(start + items_per_worker, total_items)
            if start >= total_items:
                break
            cursor_configs.append({
                "batch_id": f"{i + 1:03d}",
                "start_cursor": start,
                "end_cursor": end,
                "batch_size": end - start,
            })

        return StepHandlerResult.success(
            result={
                "batch_processing_outcome": {
                    "type": "create_batches",
                    "worker_template_name": "data_export_batch",
                    "worker_count": len(cursor_configs),
                    "cursor_configs": cursor_configs,
                    "total_items": total_items,
                },
                "analyzed_at": datetime.now(timezone.utc).isoformat(),
            }
        )

    def _process_batch(
        self, context: StepContext, batch_inputs: dict
    ) -> StepHandlerResult:
        if batch_inputs.get("is_no_op"):
            return StepHandlerResult.success(
                result={
                    "batch_id": batch_inputs.get(
                        "cursor", {}
                    ).get("batch_id", "no_op"),
                    "no_op": True,
                    "processed_count": 0,
                }
            )

        cursor = batch_inputs.get("cursor", {})
        start = cursor.get("start_cursor", 0)
        end = cursor.get("end_cursor", 0)
        batch_id = cursor.get("batch_id", "unknown")

        # Process items in the batch range
        items_processed = end - start

        return StepHandlerResult.success(
            result={
                "items_processed": items_processed,
                "items_succeeded": items_processed,
                "items_failed": 0,
                "batch_id": batch_id,
            }
        )
```

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

For a complete walkthrough of building a multi-step workflow with templates, see [Your First Workflow](first-workflow.md).

## Why Rust Has Only Step Handler

Rust's standard library and ecosystem already provide the patterns that the specialized handler types encapsulate:

- **API calls**: `reqwest` or `hyper` with Rust's `Result` type for error classification
- **Decision routing**: `match` expressions with exhaustiveness checking
- **Batch processing**: `rayon` for data parallelism, iterators with `.chunks()` for batching

The specialized handler types exist to give Python, Ruby, and TypeScript developers a structured pattern for these common operations. Rust developers get that structure from the language itself.
