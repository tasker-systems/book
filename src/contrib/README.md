# Framework Integrations

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

Each plugin provides templates for all [handler types](../getting-started/handler-types.md): step, API, decision, and batchable (Rust provides step handler only).

## Example Applications

Four fully working apps demonstrate the same five workflow patterns, each using its SDK's idiomatic style. See the [Example Apps](example-apps.md) page for details on running them and what they demonstrate.

## Getting Started

- **[Quick Start](../building/quick-start.md)** — Clone an example app and run it in 5 minutes
- **[Using tasker-ctl](../building/tasker-ctl.md)** — Bootstrap a project with the CLI tool
- **[Choosing Your Package](../getting-started/choosing-your-package.md)** — Which language SDK fits your project

## Source Repository

[tasker-systems/tasker-contrib](https://github.com/tasker-systems/tasker-contrib) on GitHub.
