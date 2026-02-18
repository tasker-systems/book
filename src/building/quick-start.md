# Quick Start

Two paths to a running Tasker workflow. Pick the one that fits your style.

## Path A: Clone an Example App (5 minutes)

The fastest way to see Tasker in action. The [example apps](../contrib/README.md) provide fully working projects in all four languages, running against published packages via Docker Compose.

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

### 3. Wait for orchestration to be healthy

```bash
curl -sf http://localhost:8080/health
```

### 4. Pick a framework and run it

Each app has its own setup instructions. For example, with Python (FastAPI):

```bash
cd fastapi-app
uv sync
uv run uvicorn app.main:app --port 8083
```

Or with Ruby (Rails):

```bash
cd rails-app
bundle install
bin/rails server -p 8082
```

### 5. Submit a task

```bash
# Submit an e-commerce order processing task
curl -X POST http://localhost:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "ecommerce_order_processing",
    "initiator": "quickstart",
    "context": {
      "order_id": "ORD-001",
      "customer_email": "test@example.com",
      "items": [{"sku": "WIDGET-A", "price": 29.99, "quantity": 2}]
    }
  }'
```

The orchestration engine coordinates the workflow — validating the order, reserving inventory, charging payment, and sending notifications — with each step handled by your chosen framework's app.

### What you just ran

Each example app implements five real-world workflow patterns:

| Pattern | Workflow | Story |
|---------|----------|-------|
| Linear pipeline | E-commerce Order Processing | [Post 01](../stories/post-01-ecommerce-checkout.md) |
| Parallel DAG | Data Pipeline Analytics | [Post 02](../stories/post-02-data-pipeline.md) |
| Diamond convergence | Microservices User Registration | [Post 03](../stories/post-03-microservices-coordination.md) |
| Namespace isolation | Customer Success Refund | [Post 04](../stories/post-04-team-scaling.md) |
| Cross-team coordination | Payments Compliance | [Post 04](../stories/post-04-team-scaling.md) |

See the [Example Apps](../contrib/example-apps.md) page for full details on each app, or read the [Engineering Stories](../stories/README.md) for the narrative walkthrough.

## Path B: Bootstrap with tasker-ctl (10 minutes)

Build a project from scratch using Tasker's CLI tool.

### Prerequisites

- **Docker** and **Docker Compose** (for Tasker infrastructure)
- **Rust toolchain** (for installing tasker-ctl)
- Your preferred language runtime (Python, Ruby, Node/Bun, or Rust)

### 1. Install tasker-ctl

```bash
cargo install tasker-ctl
```

### 2. Initialize a new project

```bash
mkdir my-tasker-project && cd my-tasker-project
tasker-ctl init --language python
```

This creates the project structure with configuration files, a `docker-compose.yml` for Tasker infrastructure, and a starter handler.

### 3. Generate a handler

```bash
tasker-ctl template generate step_handler \
  --plugin tasker-contrib-python \
  --param name=ProcessOrder
```

This generates a handler class with the standard Tasker contract — `call()` method, context access, and result formatting.

### 4. Define a task template

```bash
tasker-ctl template generate task_template \
  --plugin tasker-contrib-python \
  --param name=OrderProcessing \
  --param namespace=default
```

Edit the generated YAML to wire your handler into the workflow DAG.

### 5. Start infrastructure and run

```bash
docker compose up -d          # Start PostgreSQL, orchestration, messaging
# Start your app (language-specific)
```

### 6. Submit a task

```bash
curl -X POST http://localhost:8080/api/v1/tasks \
  -H "Content-Type: application/json" \
  -d '{
    "name": "order_processing",
    "initiator": "quickstart",
    "context": {"order_id": "ORD-001"}
  }'
```

## Next Steps

- **[Your First Handler](first-handler.md)** — Detailed walkthrough of handler anatomy and registration
- **[Your First Workflow](first-workflow.md)** — Build a multi-step DAG with dependencies
- **[Handler Types](../getting-started/handler-types.md)** — Learn about API, Decision, and Batchable handlers
