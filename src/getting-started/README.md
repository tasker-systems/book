# Getting Started

Tasker is a distributed workflow orchestration system that coordinates complex, multi-step processes across services and languages. It provides:

- **Task Orchestration** — Define workflows as directed acyclic graphs (DAGs) with dependency management
- **Multi-Language Support** — Write handlers in Rust, Ruby, Python, or TypeScript
- **Built-in Resilience** — Automatic retries, error handling, and state persistence
- **Event-Driven Architecture** — PGMQ and RabbitMQ messaging for real-time observability

## How Tasker Works

```
┌─────────────────────────────────────────────────────────────────────┐
│                        tasker-core (Rust)                           │
│  • REST + gRPC API for task submission                              │
│  • Workflow orchestration via lifecycle actors                      │
│  • Step execution and DAG dependency resolution                    │
│  • PostgreSQL state persistence                                     │
│  • Event publishing (PGMQ default, RabbitMQ optional)              │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                    ┌─────────────┼─────────────┐
                    ▼             ▼             ▼
              ┌──────────┐ ┌──────────┐ ┌──────────┐
              │  Ruby    │ │  Python  │ │TypeScript│
              │ Workers  │ │ Workers  │ │ Workers  │
              └──────────┘ └──────────┘ └──────────┘
```

You define **task templates** (YAML DAGs) that describe what steps to run and their dependencies. You write **step handlers** in your preferred language that contain the business logic. Tasker's orchestration engine executes the DAG — resolving dependencies, running independent steps in parallel, retrying failures, and persisting state.

## Understand Tasker

| Page | What you'll learn |
|------|-------------------|
| [Core Concepts](concepts.md) | Tasks, steps, handlers, templates, dependencies, and lifecycle states |
| [Handler Types](handler-types.md) | The four handler types (Step, API, Decision, Batchable) and when to use each |
| [Choosing Your Package](choosing-your-package.md) | Which language SDK fits your project |

## Ready to Build?

Once you understand the concepts, head to **[Build Your First Project](../building/README.md)** to set up your environment and write your first workflow.

If you prefer learning by example, the [Quick Start](../building/quick-start.md) gets you running a working app in 5 minutes.
