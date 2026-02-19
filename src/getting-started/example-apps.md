# Example Apps & Framework Integrations

Tasker Contrib provides two things for each supported language:

1. **CLI plugin templates** — code generators for `tasker-ctl` that scaffold handlers, task definitions, and infrastructure configuration
2. **Example applications** — fully working apps that demonstrate real-world workflow patterns against published Tasker packages

## The Integration Pattern

All four framework integrations follow the same pattern:

1. **Bootstrap** — `tasker-ctl init` creates project structure with infrastructure config
2. **Create** — `tasker-ctl template generate` scaffolds handlers and task templates
3. **Process** — Your handlers receive `StepContext`, execute business logic, return `StepHandlerResult`
4. **Query** — Use the Tasker client SDK to submit tasks and check status

The framework integration layer is intentionally thin: it translates your framework's idioms (Rails generators, FastAPI dependency injection, Bun middleware) into Tasker concepts without inventing new abstractions.

## Available Integrations

| Framework | Language | SDK Package | CLI Plugin |
|-----------|----------|-------------|------------|
| Rails | Ruby | `tasker-core-rb` | `tasker-contrib-rails` |
| FastAPI | Python | `tasker-py` | `tasker-contrib-python` |
| Hono/Bun | TypeScript | `@tasker-systems/tasker` | `tasker-contrib-typescript` |
| Axum | Rust | `tasker-worker` | `tasker-contrib-rust` |

Each plugin provides templates for all [handler types](handler-types.md): step, API, decision, and batchable (Rust provides step handler only).

## The Apps

| App | Framework | SDK Package | Source |
|-----|-----------|-------------|--------|
| **rails-app** | Rails 7 | `tasker-core-rb` | [GitHub](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app) |
| **fastapi-app** | FastAPI | `tasker-py` | [GitHub](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app) |
| **bun-app** | Hono/Bun | `@tasker-systems/tasker` | [GitHub](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app) |
| **axum-app** | Axum | `tasker-worker` | [GitHub](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app) |

## Workflow Patterns

All four apps implement the same five workflow patterns, progressing from simple to complex:

| Pattern | Workflow | Handler Types Used | Story |
|---------|----------|--------------------|-------|
| Linear pipeline | E-commerce Order Processing | Step | [Post 01](../stories/post-01-ecommerce-checkout.md) |
| Parallel DAG | Data Pipeline Analytics | Step | [Post 02](../stories/post-02-data-pipeline.md) |
| Diamond convergence | Microservices User Registration | Step | [Post 03](../stories/post-03-microservices-coordination.md) |
| Namespace isolation | Customer Success + Payments Refund | Step | [Post 04](../stories/post-04-team-scaling.md) |
| Cross-team coordination | Payments Compliance | Step | [Post 04](../stories/post-04-team-scaling.md) |

Each workflow demonstrates a specific DAG pattern. The [Engineering Stories](../stories/README.md) series teaches these patterns through progressive narrative — start with Post 01 and work forward.

## Shared Infrastructure

All example apps share a single `docker-compose.yml` that provides:

- **PostgreSQL** with PGMQ extensions — state persistence and default message queue
- **Tasker orchestration engine** — published GHCR image, handles DAG execution
- **RabbitMQ** — optional message broker for event publishing
- **Dragonfly** — Redis-compatible cache

```bash
cd examples
docker compose up -d

# Wait for orchestration to be healthy
curl -sf http://localhost:8080/health
```

Each app gets its own database (`example_rails`, `example_fastapi`, `example_bun`, `example_axum`) created by the shared `init-db.sql` script.

## Running an Example

### Python (FastAPI)

```bash
cd examples/fastapi-app
uv sync
uv run uvicorn app.main:app --port 8083
```

### Ruby (Rails)

```bash
cd examples/rails-app
bundle install
bin/rails server -p 8082
```

### TypeScript (Bun/Hono)

```bash
cd examples/bun-app
bun install
bun run dev
```

### Rust (Axum)

```bash
cd examples/axum-app
cargo run
```

## What to Study

Each app demonstrates the same concepts in its framework's idioms. Comparing across languages is the fastest way to understand Tasker's cross-language handler contract:

- **Handler registration** — How each framework discovers and registers step handlers
- **Context access** — `get_input()`, `get_dependency_result()`, and step configuration
- **Error handling** — `PermanentError` vs `RetryableError` patterns
- **Task templates** — Identical YAML DAG definitions across all four apps
- **Testing** — Each app has integration tests that submit tasks and verify results

## Getting Started

- **[Quick Start](../building/quick-start.md)** — Clone an example app and run it in 5 minutes
- **[Using tasker-ctl](../building/tasker-ctl.md)** — Bootstrap a project with the CLI tool
- **[Choosing Your Package](choosing-your-package.md)** — Which language SDK fits your project

## Source Repository

All example apps live in the [tasker-systems/tasker-contrib](https://github.com/tasker-systems/tasker-contrib) repository under `examples/`.
