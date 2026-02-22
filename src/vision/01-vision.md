# Generative Workflows, Deterministic Execution

*A Vision for Composable, LLM-Integrated Workflow Orchestration in Tasker*

---

## The Generative Foundation

Tasker Core is a workflow orchestration system built on a set of properties that, individually, are well-understood in distributed systems engineering: statelessness, horizontal scalability, event-driven processing, deterministic execution, idempotency. What makes Tasker interesting is not any single property but the *composition* of all of them — and what that composition makes possible.

The workflow step is the atomic unit of the system. Each step has a lifecycle modeled as a state machine, with execution paths, retry and backoff semantics, and transactional state transitions. Because the step is idempotent, it can be retried safely. Because its state machine is consistent, its behavior is predictable. Because it executes within a DAG of declared dependencies, the broader workflow has known ordering guarantees. Because all of this is backed by PostgreSQL transactions, the system never enters a half-built state.

These properties were designed to make Tasker reliable. But reliability, it turns out, is also what makes a system *composable* in ways that weren't necessarily planned for. When you can trust that a step will do exactly what it says — succeed, fail, or retry — you can assemble steps into novel configurations without losing the safety properties of the whole. Reliable parts enable unreliable planners.

This is the generative insight: **the determinism of the execution layer creates space for non-deterministic planning**. And the stronger the execution guarantees, the more freedom the planning layer has.

---

## What Already Exists

Tasker's conditional workflow architecture already proves the core mechanism. Three capabilities, working together, establish the precedent for everything this vision describes:

**Decision Point Steps** evaluate business logic at runtime and return the names of downstream steps that should be created. The full DAG does not need to exist at task initialization — steps downstream of a decision point are held unrealized until the decision is made.

**Dynamic Step Creation** materializes new steps transactionally. When a decision point fires, the orchestration layer creates the specified workflow steps, their edges, and their queue entries in a single database transaction. The graph grows atomically — either the entire downstream segment is created, or none of it is.

**Deferred Convergence** with intersection semantics allows the system to reconverge after dynamic branching without knowing in advance which branches were taken. A convergence step declares all *possible* upstream dependencies; at runtime, it waits only for the intersection of declared dependencies and actually-created steps. This means convergence works correctly regardless of which path the decision point chose.

Batch processing extends this further — a single batchable step can spawn N worker instances at runtime, all created transactionally, all converging through the same intersection semantics. The graph is not just branching dynamically; it is *scaling* dynamically.

These are not theoretical capabilities. They are implemented, tested, and approaching production readiness.

---

## Action Grammars: A Type System for Workflow Actions

The existing vision for dynamic workflows imagines a *handler catalog* — a library of generic, parameterized step handlers (HTTP request, data transformation, schema validation, fan-out) that can be composed without writing new code. This is valuable, but it treats the handler as the unit of composition. We can go deeper.

Consider how handlers actually work. An HTTP-calling handler does several things: it constructs a request, manages authentication, makes the call, handles errors, extracts relevant data from the response, and shapes its output for downstream consumption. A validation handler reads input, applies rules, partitions results into valid and invalid sets, and shapes its output. These handlers share lower-level actions — acquiring data, transforming shapes, asserting conditions, emitting results — even though their higher-level purposes differ.

An **action grammar** is a formalization of these lower-level actions as composable primitives with declared input and output contracts. The term "grammar" is borrowed from compositional pattern work in the Storyteller project, but the application here is grounded in distributed systems concerns rather than narrative ones. An action grammar primitive:

- **Has a single concern.** Acquire external data. Transform a data shape. Assert an invariant. Gate on a condition. Emit a notification.
- **Declares its input and output contracts.** Not as JSON Schema validated at runtime, but as Rust structs and traits enforced at compile time. Primitive A's output type must be compatible with primitive B's input type for the composition to compile.
- **Preserves execution properties.** Each primitive is idempotent, retryable, and side-effect bounded. A composition of primitives inherits these properties because the composition rules enforce them.

A handler, then, is a *composition of action grammar primitives* — a layered assembly of discrete actions where each layer's data contracts are enforced by the Rust type system. The handler catalog becomes a library of pre-composed handlers built on this grammar, rather than a flat collection of independent implementations.

This matters for two reasons. First, it gives an LLM planner a richer vocabulary than "pick a handler." The LLM can compose from primitives — "acquire data from this endpoint, validate against this schema, transform into this shape" — and the composition is guaranteed correct because the type system enforces it. Second, it makes the catalog extensible without sacrificing safety. New handlers are compositions of existing primitives, not new implementations that need independent verification.

---

## Two Trust Tiers

This architecture creates a natural separation between two levels of trust:

**Developer-authored handlers** are written in whatever language the developer's application uses — Python, Ruby, TypeScript, Rust — registered through the DSL or class-based patterns, and executed through the polyglot FFI worker infrastructure. These handlers contain business logic that the developer owns. The system routes to them, retries them, manages their lifecycle, but the correctness of what's inside is the developer's responsibility. This is the model Tasker has today, and it remains the primary developer experience.

**System-invoked action grammars** are the primitives and compositions that an LLM assembles into workflow fragments at runtime. These are implemented in Rust because they are *the system's responsibility*. When a planner says "acquire data from this endpoint, validate against this schema, transform into this shape," the code that executes needs to be as close to provably correct as possible. Rust provides this: the composition rules are compiled, the data contracts are enforced by the type system, the side-effect boundaries are explicit. The system is not trusting a JSON configuration to be right at runtime — it is trusting that the Rust compiler already verified the composition is sound.

The action grammar tier is where certainty lives *precisely because* the planner is probabilistic. The stronger the floor beneath the planner, the more freedom the planner has to compose novel workflows. A planner that can only compose from a vocabulary it cannot break is fundamentally different from a planner that can compose from a vocabulary that might fail at runtime.

Developer-authored handlers and system-invoked action grammars coexist in the same workflow. A task template can reference both — static steps backed by application-specific handlers and dynamically planned steps backed by grammar compositions. The orchestration layer treats both as steps; the difference is in the provenance and the trust model.

---

## The From-Here-to-There Path

This vision does not require building everything before any of it is useful. There is a natural sequence of work where each step delivers real value to the Tasker ecosystem while building toward the full generative capability:

**Step 1: Templates as Generative Contracts (TAS-280).** Extend the TaskTemplate with `result_schema` on step definitions. Build `tasker-ctl generate` to produce typed handler code, result models, and test scaffolds from templates. This has immediate utility for developer quality of life — typed dependency injection, IDE autocomplete, compile-time or lint-time shape checking. But it also establishes the first data contracts in the system and makes the template a source of code generation rather than just structural description.

**Step 2: MCP Server for Workflow Authoring.** Build an MCP server that works with an LLM to help developers create well-structured templates, handler code, and test code from natural language descriptions. The MCP server validates templates for correctness, checks that handler-resolution patterns between templates and handler DSL code are valid, and generates calling code from the template's `input_schema`. This is the first point where an LLM touches the Tasker workflow lifecycle — not planning at runtime, but assisting with authoring at development time. The patterns learned here (prompt engineering, structured output quality, validation feedback loops) transfer directly to runtime planning.

**Step 3: Action Grammars and Handler Catalog.** With data contracts established and MCP server experience revealing which workflow patterns recur, build the action grammar primitives in Rust and compose the handler catalog from them. This is where the compile-time enforcement comes in — where the grammar's type system ensures that compositions are correct and the catalog provides a vocabulary that an LLM can compose from safely.

**Step 4: LLM Planning and Recursive Workflows.** With the vocabulary established and the MCP server experience informing prompt and context design, introduce planning steps that generate validated workflow fragments from runtime context, composed from action grammar primitives. Extend to recursive planning where each phase's plan is informed by accumulated results from prior phases.

Each step depends on insights from the previous one. TAS-280 reveals what data contracts look like in practice. The MCP server reveals what the LLM needs to generate correct workflow components. Both inform the action grammar design. The action grammars provide the vocabulary the planning interface requires.

---

## What This Is Not

Precision matters when describing what AI integration means within an engineering system. This vision is specifically *not* the following:

**It is not autonomous agents.** The LLM does not have persistent state, does not decide when to act, and does not operate outside the boundaries of the workflow system. Every step it plans goes through the same lifecycle, gets the same retry semantics, produces the same observability data as any other step. The system is always in control.

**It is not code generation.** The LLM does not write handlers. In the developer-assistance context (MCP server), it generates handler *scaffolds* that developers review and extend. In the runtime planning context, it *composes and parameterizes* action grammar primitives from a known catalog. There is no hot-loading of generated code, no runtime compilation, no eval. The security boundary is composition of verified primitives, not execution of generated code.

**It is not unconstrained.** Planning steps operate within explicit bounds: maximum graph depth, maximum step count, maximum cost budget, required convergence points. The orchestration layer validates every workflow fragment before materializing it. Invalid plans are rejected, not executed.

**It is not opaque.** Every planning decision is captured — the LLM's reasoning, the generated workflow fragment, the validation result, the materialized steps. The observability guarantees that apply to every Tasker step apply equally to dynamically planned steps. The provenance of every step is traceable to the planning decision that created it.

---

## The Intentional Partnership

This vision is a natural expression of the Intentional AI Partnership philosophy that guides Tasker's development.

The core insight of that philosophy — that AI amplifies existing engineering practices rather than replacing them — applies directly here. Tasker's execution guarantees (determinism, idempotency, transactional consistency, observability) are the engineering practices being amplified. The LLM adds flexibility and reasoning capability to workflow planning without undermining the properties that make the system trustworthy.

The principle of *specification before implementation* maps to the planning step's contract: the LLM produces a specification (the workflow fragment) that the system validates before implementing (materializing and executing). The principle of *human accountability as the final gate* maps to the gate handler — a catalog primitive that allows human approval at any decision point. The principle of *validation as a first-class concern* maps to the fragment validation pipeline that sits between planning and execution.

The two-tier trust model embodies the partnership concretely. Human developers write business logic in their language of choice with their domain expertise. The system provides a grammar of reliable, composable, type-safe primitives that the LLM can assemble. Neither is asked to do what the other does better. The boundaries are clean, the contracts are explicit, and the guarantees are preserved.

---

## Where This Leads

The immediate practical implication is a system where problems can be described at the level of *what needs to happen* rather than *exactly how it should be orchestrated*. Today this means a developer describes a workflow and an MCP server generates the template and handler code. Tomorrow this means a planning step receives runtime context and generates a workflow fragment from composable grammar primitives. Eventually this means multi-phase workflows where each phase adapts to what was learned in the previous phase.

The longer-term implication is a type system for workflow actions — an extensible grammar where new capabilities are compositions of existing primitives, where correctness is enforced at compile time, and where an LLM planner has a vocabulary rich enough to express complex workflows yet constrained enough that every composition is guaranteed to execute correctly.

The foundation is built. The machinery works. The extension is natural — and the path there delivers value at every step.

---

*This document is part of the Tasker Core generative workflow initiative. It describes a vision that will be realized through phased implementation, beginning with templates as generative contracts and progressing through action grammars, planning interfaces, and recursive planning capabilities.*
