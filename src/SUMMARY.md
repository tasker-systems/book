# Summary

[Introduction](README.md)
[Why Tasker?](why-tasker.md)

---

# Getting Started

- [Getting Started](getting-started/README.md)
  - [Choosing Your Package](getting-started/choosing-your-package.md)
  - [Concepts](getting-started/concepts.md)
  - [First Handler](getting-started/first-handler.md)
  - [First Workflow](getting-started/first-workflow.md)
  - [Install](getting-started/install.md)
  - [Next Steps](getting-started/next-steps.md)
  - [Python](getting-started/python.md)
  - [Ruby](getting-started/ruby.md)
  - [Rust](getting-started/rust.md)
  - [Tasker Ctl](getting-started/tasker-ctl.md)
  - [Typescript](getting-started/typescript.md)

---

# Architecture

- [Architecture Overview](architecture/README.md)
  - [Actors](architecture/actors.md)
  - [Backpressure Architecture](architecture/backpressure-architecture.md)
  - [Circuit Breakers](architecture/circuit-breakers.md)
  - [Crate Architecture](architecture/crate-architecture.md)
  - [Deployment Patterns](architecture/deployment-patterns.md)
  - [Domain Events](architecture/domain-events.md)
  - [Events And Commands](architecture/events-and-commands.md)
  - [Idempotency And Atomicity](architecture/idempotency-and-atomicity.md)
  - [Messaging Abstraction](architecture/messaging-abstraction.md)
  - [States And Lifecycles](architecture/states-and-lifecycles.md)
  - [Tasker Ctl](architecture/tasker-ctl.md)
  - [Worker Actors](architecture/worker-actors.md)
  - [Worker Event Systems](architecture/worker-event-systems.md)

---

# Guides

- [Operational Guides](guides/README.md)
  - [Api Security](guides/api-security.md)
  - [Auth Integration](guides/auth-integration.md)
  - [Batch Processing](guides/batch-processing.md)
  - [Caching](guides/caching.md)
  - [Conditional Workflows](guides/conditional-workflows.md)
  - [Configuration Management](guides/configuration-management.md)
  - [Dlq System](guides/dlq-system.md)
  - [Handler Resolution](guides/handler-resolution.md)
  - [Identity Strategy](guides/identity-strategy.md)
  - [Quick Start](guides/quick-start.md)
  - [Retry Semantics](guides/retry-semantics.md)
  - [Use Cases And Patterns](guides/use-cases-and-patterns.md)

---

# Workers

- [Worker Guides](workers/README.md)
  - [Api Convergence Matrix](workers/api-convergence-matrix.md)
  - [Client Wrapper](workers/client-wrapper.md)
  - [Example Handlers](workers/example-handlers.md)
  - [Ffi Safety](workers/ffi-safety.md)
  - [Patterns And Practices](workers/patterns-and-practices.md)
  - [Python](workers/python.md)
  - [Ruby](workers/ruby.md)
  - [Rust](workers/rust.md)
  - [Typescript](workers/typescript.md)

---

# Observability

- [Observability](observability/README.md)
  - [Benchmark Audit And Profiling Plan](observability/benchmark-audit-and-profiling-plan.md)
  - [Benchmark Implementation Decision](observability/benchmark-implementation-decision.md)
  - [Benchmark Quick Reference](observability/benchmark-quick-reference.md)
  - [Benchmark Strategy Summary](observability/benchmark-strategy-summary.md)
  - [Benchmarking Guide](observability/benchmarking-guide.md)
  - [Logging Standards](observability/logging-standards.md)
  - [Metrics Reference](observability/metrics-reference.md)
  - [Metrics Verification](observability/metrics-verification.md)
  - [Opentelemetry Improvements](observability/opentelemetry-improvements.md)

---

# Principles

- [Design Principles](principles/README.md)
  - [Composition Over Inheritance](principles/composition-over-inheritance.md)
  - [Cross Language Consistency](principles/cross-language-consistency.md)
  - [Defense In Depth](principles/defense-in-depth.md)
  - [Fail Loudly](principles/fail-loudly.md)
  - [Intentional Ai Partnership](principles/intentional-ai-partnership.md)
  - [Tasker Core Tenets](principles/tasker-core-tenets.md)
  - [Twelve Factor Alignment](principles/twelve-factor-alignment.md)
  - [Zen Of Python PEP 20](principles/zen-of-python-PEP-20.md)

---

# Vision

- [Vision](vision/README.md)
  - [01 Vision](vision/01-vision.md)
  - [02 Technical Approach](vision/02-technical-approach.md)
  - [03 Phase 1 Handler Catalog](vision/03-phase-1-handler-catalog.md)
  - [04 Phase 2 Planning Interface](vision/04-phase-2-planning-interface.md)
  - [05 Phase 3 Wasm Broker](vision/05-phase-3-wasm-broker.md)
  - [06 Phase 4 Recursive Planning](vision/06-phase-4-recursive-planning.md)
  - [07 Complexity Management](vision/07-complexity-management.md)

---

# Reference

- [Reference](reference/README.md)
  - [Ffi Boundary Types](reference/ffi-boundary-types.md)
  - [Ffi Telemetry Pattern](reference/ffi-telemetry-pattern.md)
  - [Library Deployment Patterns](reference/library-deployment-patterns.md)
  - [Sccache Configuration](reference/sccache-configuration.md)
  - [Step Context Api](reference/step-context-api.md)
  - [Table Management](reference/table-management.md)
  - [Task And Step Readiness And Execution](reference/task-and-step-readiness-and-execution.md)

---

# Generated Reference

- [Generated Reference](generated/index.md)
  - [Adr Summary](generated/adr-summary.md)
  - [Config Operational Guide](generated/config-operational-guide.md)
  - [Config Reference Common](generated/config-reference-common.md)
  - [Config Reference Complete](generated/config-reference-complete.md)
  - [Config Reference Orchestration](generated/config-reference-orchestration.md)
  - [Config Reference Worker](generated/config-reference-worker.md)
  - [Crate Dependency Graph](generated/crate-dependency-graph.md)
  - [Database Schema](generated/database-schema.md)
  - [Error Troubleshooting Guide](generated/error-troubleshooting-guide.md)
  - [State Machine Diagrams](generated/state-machine-diagrams.md)

---

# Auth

- [Authentication & Authorization](auth/README.md)
  - [Configuration](auth/configuration.md)
  - [Permissions](auth/permissions.md)
  - [Testing](auth/testing.md)

---

# Operations

- [Backpressure Monitoring](operations/backpressure-monitoring.md)
- [Checkpoint Operations](operations/checkpoint-operations.md)
- [Connection Pool Tuning](operations/connection-pool-tuning.md)
- [Mpsc Channel Tuning](operations/mpsc-channel-tuning.md)

---

# Testing

- [Cluster Testing Guide](testing/cluster-testing-guide.md)
- [Comprehensive Lifecycle Testing Guide](testing/comprehensive-lifecycle-testing-guide.md)
- [Decision Point E2e Tests](testing/decision-point-e2e-tests.md)

---

# Security

- [Alpha Audit Report](security/alpha-audit-report.md)

---

# Decisions

- [Architectural Decisions](decisions/README.md)
  - [Adr 001 Actor Pattern](decisions/adr-001-actor-pattern.md)
  - [Adr 002 Bounded Mpsc Channels](decisions/adr-002-bounded-mpsc-channels.md)
  - [Adr 003 Ownership Removal](decisions/adr-003-ownership-removal.md)
  - [Adr 004 Backoff Consolidation](decisions/adr-004-backoff-consolidation.md)
  - [Adr 005 Dual Event System](decisions/adr-005-dual-event-system.md)
  - [Adr 006 Worker Decomposition](decisions/adr-006-worker-decomposition.md)
  - [Adr 007 Ffi Over Wasm](decisions/adr-007-ffi-over-wasm.md)
  - [Adr 008 Composition Pattern](decisions/adr-008-composition-pattern.md)
  - [Adr 009 Napi Rs Replaces Koffi](decisions/adr-009-napi-rs-replaces-koffi.md)
  - [Rca Parallel Execution Timing Bugs](decisions/rca-parallel-execution-timing-bugs.md)

---

# Benchmarks

- [Benchmarks](benchmarks/README.md)
  - [E2e Benchmarks](benchmarks/e2e-benchmarks.md)

---

# Contrib

- [Framework Integrations](contrib/README.md)

---

# Stories

- [Engineering Stories](stories/README.md)
  - [Post 01 Ecommerce Checkout](stories/post-01-ecommerce-checkout.md)
  - [Post 02 Data Pipeline](stories/post-02-data-pipeline.md)
  - [Post 03 Microservices Coordination](stories/post-03-microservices-coordination.md)
  - [Post 04 Team Scaling](stories/post-04-team-scaling.md)
