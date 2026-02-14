# Resilient Data Pipelines with Tasker

*How DAG workflows and parallel execution turn brittle ETL scripts into observable, self-healing pipelines.*

## The Problem

Your analytics pipeline runs nightly. It pulls sales data from your database, inventory snapshots from the warehouse system, and customer records from the CRM. Then it transforms each dataset, aggregates everything into a unified view, and generates business insights. Eight steps, chained together in a cron job.

When the warehouse API returns a 503 at 2 AM, the entire pipeline fails. Your data team discovers the gap the next morning when dashboards show stale numbers. They re-run the whole pipeline manually, even though the sales and customer extracts completed successfully the first time. The warehouse API is back up now, but you've lost hours of freshness and burned compute re-extracting data you already had.

The root issue isn't the API failure — transient errors happen. The issue is that your pipeline treats independent data sources as a sequential chain, so one failure poisons everything downstream.

## The Fragile Approach

A typical ETL pipeline chains everything sequentially:

```python
def run_pipeline(config):
    sales = extract_sales(config.source)         # 1. blocks on completion
    inventory = extract_inventory(config.warehouse)  # 2. waits for sales (why?)
    customers = extract_customers(config.crm)     # 3. waits for inventory (why?)
    sales_t = transform_sales(sales)
    inventory_t = transform_inventory(inventory)
    customers_t = transform_customers(customers)
    metrics = aggregate(sales_t, inventory_t, customers_t)
    return generate_insights(metrics)
```

The three extract steps have no data dependency on each other, yet they run sequentially because the code is sequential. If extract #2 fails, extract #3 never starts. And there's no retry — a single transient failure aborts the whole run.

## The Tasker Approach

Tasker models this pipeline as a **DAG** (directed acyclic graph). Steps that don't depend on each other run in parallel automatically. Steps that need upstream results wait only for their specific dependencies.

### Task Template (YAML)

```yaml
name: analytics_pipeline
namespace_name: data_pipeline
version: 1.0.0
description: "Analytics ETL pipeline with parallel extraction and aggregation"

steps:
  # EXTRACT PHASE — 3 parallel steps (no dependencies)
  - name: extract_sales_data
    description: "Extract sales records from database"
    handler:
      callable: extract_sales_data
    dependencies: []
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      initial_delay: 2
      max_delay: 30

  - name: extract_inventory_data
    description: "Extract inventory records from warehouse system"
    handler:
      callable: extract_inventory_data
    dependencies: []
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      initial_delay: 2
      max_delay: 30

  - name: extract_customer_data
    description: "Extract customer records from CRM"
    handler:
      callable: extract_customer_data
    dependencies: []
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      initial_delay: 2
      max_delay: 30

  # TRANSFORM PHASE — each depends only on its own extract
  - name: transform_sales
    handler:
      callable: transform_sales
    dependencies:
      - extract_sales_data
    retry:
      retryable: true
      max_attempts: 2

  - name: transform_inventory
    handler:
      callable: transform_inventory
    dependencies:
      - extract_inventory_data
    retry:
      retryable: true
      max_attempts: 2

  - name: transform_customers
    handler:
      callable: transform_customers
    dependencies:
      - extract_customer_data
    retry:
      retryable: true
      max_attempts: 2

  # AGGREGATE PHASE — waits for ALL 3 transforms (DAG convergence)
  - name: aggregate_metrics
    handler:
      callable: aggregate_metrics
    dependencies:
      - transform_sales
      - transform_inventory
      - transform_customers
    retry:
      retryable: true
      max_attempts: 2

  # INSIGHTS PHASE — depends on aggregation
  - name: generate_insights
    handler:
      callable: generate_insights
    dependencies:
      - aggregate_metrics
    retry:
      retryable: true
      max_attempts: 2
```

The DAG structure is visible in the `dependencies` field:

```
extract_sales ──→ transform_sales ──────┐
extract_inventory → transform_inventory ─┼─→ aggregate_metrics → generate_insights
extract_customer ─→ transform_customers ─┘
```

All three extract steps have `dependencies: []`, so Tasker runs them **concurrently**. Each transform depends only on its own extract, so transforms also run in parallel (once their extract completes). The aggregate step waits for all three transforms — this is the **convergence point** where parallel branches rejoin.

> **Full template**: [data\_pipeline\_analytics\_pipeline.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/data_pipeline_analytics_pipeline.yaml)

### Step Handlers

#### ExtractSalesDataHandler — Parallel Root Step

Extract steps are "root" steps with no dependencies. They run immediately when the task starts, concurrently with other root steps.

**Python (FastAPI)**

```python
class ExtractSalesDataHandler(StepHandler):
    handler_name = "extract_sales_data"
    handler_version = "1.0.0"

    PRODUCT_CATEGORIES = ["electronics", "clothing", "food", "home", "sports"]
    REGIONS = ["us-east", "us-west", "eu-central", "ap-southeast"]

    def call(self, context: StepContext) -> StepHandlerResult:
        source = context.get_input("source") or "default"
        date_start = context.get_input("date_range_start") or "2026-01-01"
        date_end = context.get_input("date_range_end") or "2026-01-31"

        records = []
        for i in range(30):
            category = random.choice(self.PRODUCT_CATEGORIES)
            region = random.choice(self.REGIONS)
            quantity = random.randint(1, 50)
            unit_price = round(random.uniform(5.0, 500.0), 2)
            revenue = round(quantity * unit_price, 2)

            records.append({
                "record_id": f"sale_{uuid.uuid4().hex[:10]}",
                "category": category,
                "region": region,
                "quantity": quantity,
                "unit_price": unit_price,
                "revenue": revenue,
            })

        total_revenue = round(sum(r["revenue"] for r in records), 2)

        return StepHandlerResult.success(
            result={
                "source": "sales_database",
                "record_count": len(records),
                "records": records,
                "total_revenue": total_revenue,
                "date_range": {"start": date_start, "end": date_end},
                "extracted_at": datetime.now(timezone.utc).isoformat(),
            },
        )
```

**TypeScript (Bun/Hono)**

```typescript
export class ExtractSalesDataHandler extends StepHandler {
  static handlerName = 'DataPipeline.StepHandlers.ExtractSalesDataHandler';

  async call(context: StepContext): Promise<StepHandlerResult> {
    const dateRange = context.getInput<{ start: string; end: string }>('date_range');

    const recordCount = Math.floor(Math.random() * 500) + 100;
    const records = generateSalesRecords(recordCount);
    const totalRevenue = records.reduce((sum, r) => sum + r.value, 0);

    return this.success({
      records,
      extracted_at: new Date().toISOString(),
      source: 'SalesDatabase',
      total_amount: Math.round(totalRevenue * 100) / 100,
      record_count: recordCount,
    });
  }
}
```

The important detail: this handler has no `get_dependency_result()` calls. It reads only from the task's initial input via `get_input()`. The orchestrator knows it can run this step immediately, in parallel with the other two extract steps.

> **Full implementations**: [FastAPI](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/data_pipeline.py) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/data-pipeline.ts)

#### AggregateMetricsHandler — Multi-Dependency Convergence

The aggregate step is the convergence point. It depends on all three transform steps and pulls results from each one.

**Python (FastAPI)**

```python
class AggregateMetricsHandler(StepHandler):
    handler_name = "aggregate_metrics"
    handler_version = "1.0.0"

    def call(self, context: StepContext) -> StepHandlerResult:
        sales_transform = context.get_dependency_result("transform_sales")
        traffic_transform = context.get_dependency_result("transform_inventory")
        inventory_transform = context.get_dependency_result("transform_customers")

        if not all([sales_transform, traffic_transform, inventory_transform]):
            return StepHandlerResult.failure(
                message="Missing one or more transform dependency results",
                error_type=ErrorType.HANDLER_ERROR,
                retryable=False,
            )

        total_revenue = sales_transform.get("total_revenue", 0)
        total_inventory = traffic_transform.get("total_quantity_on_hand", 0)
        total_customers = inventory_transform.get("record_count", 0)

        revenue_per_customer = (
            round(total_revenue / total_customers, 2) if total_customers > 0 else 0
        )
        inventory_turnover = (
            round(total_revenue / total_inventory, 4) if total_inventory > 0 else 0
        )

        return StepHandlerResult.success(
            result={
                "total_revenue": total_revenue,
                "total_inventory_quantity": total_inventory,
                "total_customers": total_customers,
                "revenue_per_customer": revenue_per_customer,
                "inventory_turnover_indicator": inventory_turnover,
                "aggregation_complete": True,
                "sources_included": 3,
                "aggregated_at": datetime.now(timezone.utc).isoformat(),
            },
        )
```

This handler calls `get_dependency_result()` three times — once for each upstream transform. The orchestrator guarantees all three have completed successfully before this step runs. If any transform failed (after exhausting its retries), this step never executes.

> **Full implementation**: [FastAPI](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/data_pipeline.py) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/data-pipeline.ts)

### Creating a Task

Submitting the pipeline follows the same pattern as any Tasker workflow:

```python
from tasker_core import TaskerClient

client = TaskerClient()
task = client.create_task(
    name="analytics_pipeline",
    namespace="data_pipeline",
    context={
        "source": "production",
        "date_range_start": "2026-01-01",
        "date_range_end": "2026-01-31",
        "granularity": "daily",
    },
)
```

## Key Concepts

- **Parallel steps via empty dependencies**: Steps with `dependencies: []` are root steps that run concurrently. No threading code, no async coordination — the orchestrator handles it.
- **DAG convergence**: A step that depends on multiple upstream steps waits for all of them. The `aggregate_metrics` step converges three parallel branches into one.
- **Multi-dependency access**: `get_dependency_result()` retrieves the complete result from any named upstream step. The handler doesn't need to know whether that step ran in parallel or sequentially.
- **Retry with backoff**: Each step configures its own retry policy. The extract steps use 3 attempts with exponential backoff because external systems have transient failures. Transform steps use 2 attempts because they're CPU-bound and unlikely to benefit from retrying.

## Full Implementations

The complete analytics pipeline is implemented in all four supported languages:

| Language | Handlers | Template |
|----------|----------|----------|
| Ruby (Rails) | [handlers/data\_pipeline/](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/data_pipeline/) | [data\_pipeline\_analytics\_pipeline.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/data_pipeline_analytics_pipeline.yaml) |
| TypeScript (Bun/Hono) | [handlers/data-pipeline.ts](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/data-pipeline.ts) | [data\_pipeline\_analytics\_pipeline.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/config/tasker/templates/data_pipeline_analytics_pipeline.yaml) |
| Python (FastAPI) | [handlers/data\_pipeline.py](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/data_pipeline.py) | [data\_pipeline\_analytics\_pipeline.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/config/tasker/templates/data_pipeline_analytics_pipeline.yaml) |
| Rust (Axum) | [handlers/data\_pipeline.rs](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/src/handlers/data_pipeline.rs) | [data\_pipeline\_analytics\_pipeline.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/config/tasker/templates/data_pipeline_analytics_pipeline.yaml) |

## What's Next

Parallel extraction is powerful, but real-world workflows often have a **diamond pattern** — a step that fans out to parallel branches that must converge before continuing. In [Post 03: Microservices Coordination](post-03-microservices-coordination.md), we'll build a user registration workflow where account creation fans out to billing and preferences setup in parallel, then converges for the welcome sequence — demonstrating how Tasker replaces custom circuit breakers with declarative dependency management.
