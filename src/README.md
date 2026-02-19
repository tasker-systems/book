# Tasker

**Workflow orchestration that meets your code where it lives.**

Tasker is an open-source workflow orchestration engine built on PostgreSQL and PGMQ. You define workflows as task templates with ordered steps, implement handlers in Rust, Ruby, Python, or TypeScript, and the engine handles execution, retries, circuit breaking, and observability.

Your existing business logic — API calls, database operations, service integrations — becomes a distributed, event-driven, retryable workflow with minimal ceremony. No DSLs to learn, no framework rewrites. Just thin handler wrappers around code you already have.

---

## Get Started

<div style="display: grid; grid-template-columns: repeat(2, 1fr); gap: 16px; margin: 24px 0;">

<div style="border: 1px solid #ccc; border-radius: 8px; padding: 16px;">

**[Getting Started Guide](getting-started/README.md)**

From zero to your first workflow. Install, write a handler, define a template, submit a task, and watch it run.

</div>

<div style="border: 1px solid #ccc; border-radius: 8px; padding: 16px;">

**[Why Tasker?](why-tasker.md)**

An honest look at where Tasker fits in the workflow orchestration landscape — and where established tools might be a better choice.

</div>

<div style="border: 1px solid #ccc; border-radius: 8px; padding: 16px;">

**[Architecture](architecture/README.md)**

How Tasker works under the hood: actors, state machines, event systems, circuit breakers, and the PostgreSQL-native execution model.

</div>

<div style="border: 1px solid #ccc; border-radius: 8px; padding: 16px;">

**[Configuration Reference](generated/index.md)**

Complete reference for all 246 configuration parameters across orchestration, workers, and shared settings.

</div>

</div>

---

## Choose Your Language

Tasker is polyglot from the ground up. The orchestration engine is Rust; workers can be any of four languages, all sharing the same core abstractions expressed idiomatically.

| Language | Package | Install | Registry |
|----------|---------|---------|----------|
| **Rust** | `tasker-client` / `tasker-worker` | `cargo add tasker-client tasker-worker` | [crates.io](https://crates.io/users/jcoletaylor) |
| **Ruby** | `tasker-rb` | `gem install tasker-rb` | [rubygems.org](https://rubygems.org/gems/tasker-rb) |
| **Python** | `tasker-py` | `pip install tasker-py` | [pypi.org](https://pypi.org/project/tasker-py/) |
| **TypeScript** | `@tasker-systems/tasker` | `npm install @tasker-systems/tasker` | [npmjs.com](https://www.npmjs.com/package/@tasker-systems/tasker) |

Each language guide covers installation, handler patterns, testing, and production considerations:

**[Rust](workers/rust.md)** · **[Ruby](workers/ruby.md)** · **[Python](workers/python.md)** · **[TypeScript](workers/typescript.md)**

---

## Explore the Documentation

### For New Users

- **[Core Concepts](getting-started/concepts.md)** — Tasks, steps, handlers, templates, and namespaces
- **[Choosing Your Package](getting-started/choosing-your-package.md)** — Which package do you need?
- **[Quick Start](guides/quick-start.md)** — Running in 5 minutes

### Architecture & Design

- **[Architecture Overview](architecture/README.md)** — System design and component interaction
- **[Design Principles](principles/README.md)** — The tenets behind Tasker's design decisions
- **[Architectural Decisions](decisions/README.md)** — ADRs documenting key technical choices

### Operational Guides

- **[Handler Resolution](guides/handler-resolution.md)** — How Tasker finds and runs your handlers
- **[Retry Semantics](guides/retry-semantics.md)** — Retry strategies, backoff, and circuit breaking
- **[Batch Processing](guides/batch-processing.md)** — Processing work in batches
- **[DLQ System](guides/dlq-system.md)** — Dead letter queue for failed tasks
- **[Observability](observability/README.md)** — Metrics, tracing, and logging

### Reference

- **[Configuration Reference](generated/index.md)** — All 246 parameters documented
- **[Worker API Convergence](workers/api-convergence-matrix.md)** — Cross-language API alignment
- **[FFI Safety](workers/ffi-safety.md)** — How polyglot workers communicate safely

### Framework Integrations

- **[Example Apps & Integrations](getting-started/example-apps.md)** — Rails, FastAPI, Axum, and Bun integrations with working example projects

---

## Engineering Stories

A progressive-disclosure blog series teaching Tasker concepts through real-world scenarios. Each story follows an engineering team as they adopt workflow orchestration, with working code examples across all four languages.

| Story | What You'll Learn |
|-------|-------------------|
| **01: E-commerce Checkout** | Basic workflows, error handling, retry patterns |
| **02: Data Pipeline Resilience** | ETL orchestration, resilience under failure |
| **03: Microservices Coordination** | Cross-service workflows, distributed tracing |
| **04: Team Scaling** | Namespace isolation, multi-team patterns |
| **05: Observability** | OpenTelemetry integration, domain events |
| **06: Batch Processing** | Batch step patterns, throughput optimization |
| **07: Conditional Workflows** | Decision handlers, approval flows |
| **08: Production Debugging** | DLQ investigation, diagnostics tooling |

*Stories are being rewritten for the current Tasker architecture. [View archive →](stories/README.md)*

---

## The Project

Tasker is open-source software (MIT license) built by an engineer who has spent years designing workflow systems at multiple organizations — and finally had the opportunity to build the one that was always in his head.

It's not venture-backed. It's not chasing a market. It's a labor of love built for the engineering community.

**[Read the full story →](why-tasker.md)**

### Source Repositories

| Repository | Description |
|------------|-------------|
| [tasker-core](https://github.com/tasker-systems/tasker-core) | Rust orchestration engine, polyglot workers, and CLI |
| [tasker-contrib](https://github.com/tasker-systems/tasker-contrib) | Framework integrations and community packages |
| [tasker-book](https://github.com/tasker-systems/tasker-book) | This documentation site |
