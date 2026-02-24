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

The vision for dynamic workflows begins with a vocabulary of composable, type-safe action primitives — not a static catalog of pre-built handlers, but a *grammar* from which handlers can be composed.

Consider how handlers actually work. An HTTP-calling handler does several things: it constructs a request, manages authentication, makes the call, handles errors, extracts relevant data from the response, and shapes its output for downstream consumption. A validation handler reads input, applies rules, partitions results into valid and invalid sets, and shapes its output. These handlers share lower-level actions — acquiring data, transforming shapes, asserting conditions, emitting results — even though their higher-level purposes differ.

An **action grammar** is a formalization of these lower-level actions as composable primitives with declared input and output contracts. The term "grammar" is borrowed from compositional pattern work in the Storyteller project, but the application here is grounded in distributed systems concerns rather than narrative ones.

The fundamental unit is **`action(resource)`** — a verb applied to a noun. `Acquire(HttpEndpoint)`. `Transform(JsonPayload)`. `Validate(Schema)`. `Persist(DatabaseRow)`. Every action implies directionality — a "from" and a "to" — and every action operates on a typed resource. When actions compose, the chain is always `action(resource) → action(resource)`, where the output resource of one action becomes the input resource of the next.

An action grammar primitive:

- **Has a single concern.** Acquire external data. Transform a data shape. Assert an invariant. Gate on a condition. Emit a notification. Persist a mutation.
- **Declares its input and output contracts.** As Rust structs and traits enforced at compile time. Primitive A's output type must be compatible with primitive B's input type for the composition to compile.
- **Preserves execution properties.** Each primitive is idempotent, retryable, and side-effect bounded. A composition of primitives inherits these properties because the composition rules enforce them.

**The single-mutation boundary.** The grammar distinguishes between *non-mutating* actions (reads, transforms, validations, calculations) and *mutating* actions (creates, updates, deletes against external systems — a database, an API, a message queue). A valid composition may contain an arbitrary number of non-mutating actions but has **at most one external mutation**, and that mutation is the composition's commitment point. Everything before the mutation is preparatory, idempotent, and safely retryable. The mutation itself is the boundary where the composition has its external effect. Nothing after the mutation should be fallible in a way that would trigger re-execution of the mutation.

This structural rule is what makes compositions safe — not whether they were assembled in advance or at runtime. If the grammar enforces the single-mutation boundary and the contracts chain correctly, the composition is safe. The primitives are Rust-native and compile-time verified. The composition rules are checkable at assembly time. The safety comes from the *shape* of valid compositions, not from when they were assembled.

The "grammar" metaphor is deliberate and important. A grammar defines what sentences are expressible in a language. A dictionary is a useful collection of known sentences, but it is not the language — the grammar is. In the same way, a library of common handler patterns is a useful collection of known compositions, but it is not the full vocabulary of what can be expressed. The grammar is.

A handler, then, is a **composition of `action(resource)` primitives** — assembled to fit a specific problem's requirements, validated against the grammar's composition rules (contracts chain, single-mutation boundary, configuration well-formed), and executed with full lifecycle guarantees. A composition like `Acquire(HttpSource) → Transform(SchemaExtract) → Validate(ContractCheck) → Persist(DatabaseRow)` is validated once at assembly time and then executes as a single step with a single lifecycle.

**Common patterns** — `http_request`, `transform_and_validate`, `fan_out_aggregate` — are named, documented, well-tested composition specifications that any client can reference by name. They are a convenience library: recipes that make common operations easy to use. But at runtime, they resolve to the same grammar composition as any other handler. There is one composition model, one validation path, one execution path. The grammar's vocabulary is open, not enumerated.

---

## Two Trust Tiers

This architecture creates a natural separation between two levels of trust:

**Developer-authored handlers** are written in whatever language the developer's application uses — Python, Ruby, TypeScript, Rust — registered through the DSL or class-based patterns, and executed through the polyglot FFI worker infrastructure. These handlers contain business logic that the developer owns. The system routes to them, retries them, manages their lifecycle, but the correctness of what's inside is the developer's responsibility. This is the model Tasker has today, and it remains the primary developer experience.

**System-invoked action grammars** are the primitives and compositions that the system executes on behalf of planners and agents. These are implemented in Rust because they are *the system's responsibility*. When a planner says "acquire data from this endpoint, validate against this schema, transform into this shape, persist the result," the code that executes needs to be as close to provably correct as possible. Rust provides this: each primitive's implementation is compiled with full type safety. Composition rules — contract compatibility, single-mutation boundary, configuration validity — are enforced at assembly time before any execution occurs. The safety comes from the grammar's structural invariants: the primitives are correct because they're compiled Rust, and the compositions are correct because the grammar rules prevent invalid assembly.

The action grammar tier is where certainty lives *precisely because* the planner is probabilistic. The stronger the floor beneath the planner, the more freedom the planner has to compose novel workflows. A planner that can only compose from a vocabulary it cannot break is fundamentally different from a planner that can compose from a vocabulary that might fail at runtime.

Developer-authored handlers and system-invoked action grammars coexist in the same workflow. A task template can reference both — static steps backed by application-specific handlers and dynamically planned steps backed by grammar compositions. The orchestration layer treats both as steps; the difference is in the provenance and the trust model.

---

## Agent Integration: Deterministic Infrastructure for Autonomous Clients

The properties that make Tasker valuable for human-designed workflows — parallel execution with convergence, conditional branching, batch fan-out/fan-in, result aggregation, bounded resource consumption — are the same properties that autonomous agents need when they cannot hold everything in context at once.

The most powerful capability of agent systems is not that they reason — it's that they *delegate*. An effective agent decomposes problems: spinning up sub-agents for research, parallelizing analysis across multiple sources, aggregating findings, and making decisions with the benefit of structured, converged information. This decomposition needs infrastructure — and workflow orchestration is exactly that infrastructure.

**Tasker is not an agent framework.** It does not manage agent state, control agent behavior, or coordinate agent-to-agent communication. **Tasker is deterministic infrastructure that agents use as clients.** An agent submitting a task to Tasker is indistinguishable from a human developer or an application submitting a task. The same API, the same guarantees, the same resource controls, the same observability.

The critical insight is about *context decomposition*. When an agent is asked to design a workflow or make a complex decision, it doesn't have to "get it right" in a single reasoning pass. It can create a Tasker task — a research workflow — that fans out investigation across multiple dimensions, converges the findings, and delivers structured results that the agent uses as input to its actual decision. The `parent_correlation_id` field traces the lineage from research task to design decision to workflow execution, providing full observability of the agent's reasoning chain through Tasker's standard telemetry.

This pattern requires no new orchestration machinery. Task creation is an existing API. `parent_correlation_id` is an existing field. Fan-out/fan-in is existing behavior. Convergence semantics are existing behavior. What needs to be built are the *patterns and templates* that make this easy — research task templates, analysis step handlers, convergence-to-decision patterns — not new orchestration features.

The MCP server (Phase 0) becomes the natural integration point for agents interacting with Tasker at design time: inspecting templates, querying action grammar vocabulary, validating compositions, and understanding schema contracts. Task submission — the runtime interaction — goes through the standard Tasker API.

See [Agent Orchestration](05-agent-orchestration.md) for the full treatment of this capability.

---

## The From-Here-to-There Path

This vision does not require building everything before any of it is useful. There is a natural sequence of work where each step delivers real value to the Tasker ecosystem while building toward the full generative capability:

**Step 1: Templates as Generative Contracts (TAS-280).** Extend the TaskTemplate with `result_schema` on step definitions. Build `tasker-ctl generate` to produce typed handler code, result models, and test scaffolds from templates. This has immediate utility for developer quality of life — typed dependency injection, IDE autocomplete, compile-time or lint-time shape checking. But it also establishes the first data contracts in the system and makes the template a source of code generation rather than just structural description.

**Step 2: MCP Server and Shared Tooling.** Build an MCP server that works with an LLM to help developers (and agents) create well-structured templates, handler code, and test code from natural language descriptions. Extract the shared logic between `tasker-ctl` and `tasker-mcp` into a `tasker-tooling` crate — template validation, schema inspection, codegen, handler resolution checking — so both interfaces consume the same capabilities. This is the first point where an LLM touches the Tasker workflow lifecycle, and the first integration point for agent clients.

**Step 3: Action Grammars.** With data contracts established and MCP server experience revealing which workflow patterns recur, build the `action(resource)` grammar primitives in Rust. Establish the composition framework with contract validation and single-mutation-boundary enforcement. Build a library of common patterns as named, documented composition specifications. Any client — human, LLM, or agent — can compose handlers from the grammar vocabulary, validated against the same structural rules.

**Step 4: LLM Planning and Recursive Workflows.** With the vocabulary established and the MCP server experience informing prompt and context design, introduce planning steps that generate validated workflow fragments from runtime context, composed from action grammar primitives. Extend to recursive planning where each phase's plan is informed by accumulated results from prior phases. Agent-initiated planning — where the agent creates tasks containing planning steps — composes naturally with this infrastructure.

Each step depends on insights from the previous one. TAS-280 reveals what data contracts look like in practice. The MCP server reveals what the LLM needs to generate correct workflow components. Both inform the action grammar design. The action grammars provide the vocabulary the planning interface requires. Agent integration is a cross-cutting capability that becomes richer at each step.

---

## What This Is Not

Precision matters when describing what AI integration means within an engineering system. This vision is specifically *not* the following:

**It is not an agent orchestration framework.** Tasker does not manage agent state, does not decide when agents should act, and does not coordinate agent-to-agent communication. Agents are external clients that use Tasker's execution guarantees for their own purposes. The system provides infrastructure, not agency. The distinction is fundamental: an agent framework would require abandoning the determinism that makes Tasker trustworthy; agent-accessible infrastructure preserves it.

**It is not code generation.** The LLM does not write handlers. In the developer-assistance context (MCP server), it generates handler *scaffolds* that developers review and extend. In the runtime planning context, it *composes and parameterizes* `action(resource)` grammar primitives. There is no hot-loading of generated code, no runtime compilation, no eval. The security boundary is composition of verified primitives, not execution of generated code.

**It is not unconstrained.** Planning steps operate within explicit bounds: maximum graph depth, maximum step count, maximum cost budget, required convergence points. Agent-created tasks are subject to the same resource controls as any task. The orchestration layer validates every workflow fragment before materializing it. Invalid plans are rejected, not executed. Agents that exceed delegation budgets fail cleanly.

**It is not opaque.** Every planning decision is captured — the LLM's reasoning, the generated workflow fragment, the validation result, the materialized steps. Agent-created task chains are traceable through `parent_correlation_id`. The observability guarantees that apply to every Tasker step apply equally to dynamically planned steps and agent-created steps. The provenance of every step — including which grammar composition was used — is traceable to the decision that created it.

---

## The Intentional Partnership

This vision is a natural expression of the Intentional AI Partnership philosophy that guides Tasker's development.

The core insight of that philosophy — that AI amplifies existing engineering practices rather than replacing them — applies directly here. Tasker's execution guarantees (determinism, idempotency, transactional consistency, observability) are the engineering practices being amplified. The LLM adds flexibility and reasoning capability to workflow planning without undermining the properties that make the system trustworthy.

The principle of *specification before implementation* maps to the planning step's contract: the LLM produces a specification (the workflow fragment) that the system validates before implementing (materializing and executing). The principle of *human accountability as the final gate* maps to the gate primitive — an `action(resource)` that allows human approval at any decision point. The principle of *validation as a first-class concern* maps to the fragment validation pipeline that sits between planning and execution.

The two-tier trust model embodies the partnership concretely. Human developers write business logic in their language of choice with their domain expertise. The system provides a grammar of reliable, composable, type-safe primitives that LLMs and agents can assemble. Neither is asked to do what the other does better. The boundaries are clean, the contracts are explicit, and the guarantees are preserved.

Agent integration extends this partnership model. The agent brings reasoning and context decomposition — the ability to recognize that a problem needs investigation before design, and to structure that investigation effectively. Tasker brings deterministic execution — the guarantee that every research step completes reliably, every convergence is transactionally sound, and every result is observable. The agent delegates what it cannot do well (reliable parallel execution with convergence). Tasker delegates what it cannot do at all (reasoning about what to investigate and how to interpret findings).

---

## Where This Leads

The immediate practical implication is a system where problems can be described at the level of *what needs to happen* rather than *exactly how it should be orchestrated*. Today this means a developer describes a workflow and an MCP server generates the template and handler code. Tomorrow this means a planning step receives runtime context and generates a workflow fragment from composable grammar primitives. Eventually this means agents that can investigate, plan, and execute complex workflows — using Tasker's deterministic infrastructure for every phase of that process.

The longer-term implication is a type system for workflow actions — an extensible grammar of `action(resource)` primitives where new capabilities are compositions of existing primitives, where correctness is enforced by the grammar's structural invariants (contract compatibility, single-mutation boundary), and where any client — human, LLM, or agent — has a vocabulary rich enough to express complex workflows yet constrained enough that every composition is guaranteed to execute correctly.

The foundation is built. The machinery works. The extension is natural — and the path there delivers value at every step.

---

*This document is part of the Tasker Core generative workflow initiative. It describes a vision that will be realized through phased implementation, beginning with templates as generative contracts and progressing through action grammars, agent integration, planning interfaces, and recursive planning capabilities.*
