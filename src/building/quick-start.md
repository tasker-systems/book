# Quick Start

Two paths to a running Tasker workflow. Pick the one that fits your style.

## Path A: Clone an Example App (5 minutes)

The fastest way to see Tasker in action. The [example apps](../getting-started/example-apps.md) provide fully working projects in all four languages, running against published packages via Docker Compose.

### Prerequisites

- **Docker** and **Docker Compose**
- **curl** (or any HTTP client)

### 1. Clone tasker-contrib

```bash
git clone https://github.com/tasker-systems/tasker-contrib.git
cd tasker-contrib/examples
```

### 2. Start the infrastructure

```bash
docker compose up -d
```

This starts PostgreSQL (with PGMQ), the Tasker orchestration engine, RabbitMQ, and Dragonfly (cache). All services use published GHCR images — no local builds needed.

> **Apple Silicon**: The compose file includes `platform: linux/amd64` for Tasker images. Ensure "Use Rosetta" is enabled in Docker Desktop.

### 3. Wait for orchestration to be healthy

```bash
# Retry until healthy (up to 60 seconds on first pull)
until curl -sf http://localhost:8080/health > /dev/null; do
  echo "Waiting for orchestration..."
  sleep 5
done
echo "Orchestration is healthy"
```

### 4. Pick a framework and run it

Each app has its own setup instructions. For example, with Ruby (Rails):

```bash
cd rails-app
bundle install
bin/rails db:create db:migrate
bin/rails server -p 3000
```

Or with Python (FastAPI):

```bash
cd fastapi-app
uv sync
uv run alembic upgrade head
uv run uvicorn app.main:app --port 8000
```

### 5. Submit a task

```bash
# Submit an e-commerce order processing task
curl -X POST http://localhost:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ecommerce_order_processing",
    "namespace": "ecommerce_rb",
    "version": "1.0.0",
    "initiator": "quickstart",
    "source_system": "cli",
    "reason": "Quick-start verification",
    "context": {
      "cart_items": [
        {"sku": "WIDGET-001", "name": "Widget", "quantity": 2, "unit_price": 29.99}
      ],
      "customer_email": "test@example.com"
    }
  }'
```

The orchestration engine coordinates the workflow — validating the cart, processing payment, reserving inventory, creating the order, and sending confirmation — with each step handled by your chosen framework's app.

### What you just ran

Each example app implements four real-world workflow patterns:

| Pattern | Workflow | Story |
|---------|----------|-------|
| Linear pipeline | E-commerce Order Processing | [Post 01](../stories/post-01-ecommerce-checkout.md) |
| Parallel DAG | Data Pipeline Analytics | [Post 02](../stories/post-02-data-pipeline.md) |
| Diamond convergence | Microservices User Registration | [Post 03](../stories/post-03-microservices-coordination.md) |
| Namespace isolation | Team Scaling (Customer Success + Payments) | [Post 04](../stories/post-04-team-scaling.md) |

See the [Example Apps](../getting-started/example-apps.md) page for full details, or read the [Engineering Stories](../stories/README.md) for narrative walkthroughs.

## Path B: Bootstrap with tasker-ctl (10 minutes)

Build a project from scratch using Tasker's CLI tool. This path generates handler scaffolding, task templates, and infrastructure configuration — everything you need to start writing business logic.

### Prerequisites

- **Docker** and **Docker Compose** (for Tasker infrastructure)
- **Rust toolchain** (for installing `tasker-ctl`)
- Your preferred language runtime (Python, Ruby, Bun/Node, or Rust)

### 1. Install and initialize

```bash
cargo install tasker-ctl

mkdir my-tasker-project && cd my-tasker-project
tasker-ctl init
tasker-ctl remote update
```

This creates a `.tasker-ctl.toml` configured with the [tasker-contrib](https://github.com/tasker-systems/tasker-contrib) remote, then fetches the community templates to your local cache.

### 2. See what's available

```bash
tasker-ctl template list
```

Templates are organized by language and type:

| Template | Languages | Description |
|----------|-----------|-------------|
| `step_handler` | Ruby, Python, TypeScript, Rust | Basic step handler with test |
| `step_handler_api` | Ruby, Python, TypeScript | HTTP API handler with client |
| `step_handler_decision` | Ruby, Python, TypeScript | Decision/routing handler |
| `step_handler_batchable` | Ruby, Python, TypeScript | Parallel batch processing handler |
| `task_template` | All | Task definition YAML with step DAG |
| `docker_compose` | Ops | Docker Compose stack for Tasker services |
| `config` | Ops | TOML configuration files |

Filter by language to see just your stack:

```bash
tasker-ctl template list --language python
```

### 3. Generate a handler

```bash
tasker-ctl template generate step_handler \
  --language python \
  --param name=ProcessOrder
```

This generates `process_order_handler.py` and `tests/test_process_order_handler.py` with the standard Tasker handler contract already implemented.

### 4. Generate a task template

```bash
tasker-ctl template generate task_template \
  --language python \
  --param name=OrderProcessing \
  --param namespace=default \
  --param handler_callable=handlers.process_order_handler.ProcessOrderHandler
```

This generates `order_processing.yaml` — a task definition with one step wired to your handler. Edit it to add more steps and build a DAG.

### 5. Generate infrastructure

```bash
# Docker Compose stack (PostgreSQL + orchestration, optionally RabbitMQ + Dragonfly)
tasker-ctl template generate docker_compose \
  --plugin tasker-contrib-ops \
  --param name=myproject

# TOML configuration files (from tasker-contrib/config/tasker base configs)
tasker-ctl config generate --remote tasker-contrib \
  --context orchestration --environment development --output config/orchestration.toml
tasker-ctl config generate --remote tasker-contrib \
  --context worker --environment development --output config/worker.toml
```

### 6. Start infrastructure and submit

```bash
docker compose up -d

# Wait for health
until curl -sf http://localhost:8080/health > /dev/null; do sleep 5; done

# Submit a task
curl -X POST http://localhost:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order_processing",
    "namespace": "default",
    "version": "1.0.0",
    "initiator": "quickstart",
    "source_system": "cli",
    "reason": "First task",
    "context": {"order_id": "ORD-001"}
  }'
```

### What you just built

Path B gives you project scaffolding — handler code, task template YAML, and infrastructure config. To wire a handler into a running worker, you'll need to integrate it with a framework (Rails, FastAPI, Bun, or Axum) that starts a Tasker worker at boot. See the [language guides](README.md#language-guides) for that next step, or study the [example apps](../getting-started/example-apps.md) for complete working implementations.

## Next Steps

- **[Your First Handler](first-handler.md)** — Detailed walkthrough of handler anatomy
- **[Your First Workflow](first-workflow.md)** — Build a multi-step DAG with dependencies
- **[Using tasker-ctl](tasker-ctl.md)** — Full CLI reference for project scaffolding
