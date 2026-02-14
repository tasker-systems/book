# Probabilistic Planning, Deterministic Execution

*A Vision for LLM-Integrated Workflow Orchestration in Tasker*

---

## The Generative Foundation

Tasker Core is a workflow orchestration system built on a set of properties that, individually, are well-understood in distributed systems engineering: statelessness, horizontal scalability, event-driven processing, deterministic execution, idempotency. What makes Tasker interesting is not any single property but the *composition* of all of them — and what that composition makes possible.

The workflow step is the atomic unit of the system. Each step has a lifecycle modeled as a state machine, with execution paths, retry and backoff semantics, and transactional state transitions. Because the step is idempotent, it can be retried safely. Because its state machine is consistent, its behavior is predictable. Because it executes within a DAG of declared dependencies, the broader workflow has known ordering guarantees. Because all of this is backed by PostgreSQL transactions, the system never enters a half-built state.

These properties were designed to make Tasker reliable. But reliability, it turns out, is also what makes a system *composable* in ways that weren't necessarily planned for. When you can trust that a step will do exactly what it says — succeed, fail, or retry — you can assemble steps into novel configurations without losing the safety properties of the whole. Reliable parts enable unreliable planners.

This is the generative insight: **the determinism of the execution layer creates space for non-deterministic planning**.

---

## What Already Exists

Tasker's conditional workflow architecture already proves the core mechanism. Three capabilities, working together, establish the precedent for everything this vision describes:

**Decision Point Steps** evaluate business logic at runtime and return the names of downstream steps that should be created. The full DAG does not need to exist at task initialization — steps downstream of a decision point are held unrealized until the decision is made.

**Dynamic Step Creation** materializes new steps transactionally. When a decision point fires, the orchestration layer creates the specified workflow steps, their edges, and their queue entries in a single database transaction. The graph grows atomically — either the entire downstream segment is created, or none of it is.

**Deferred Convergence** with intersection semantics allows the system to reconverge after dynamic branching without knowing in advance which branches were taken. A convergence step declares all *possible* upstream dependencies; at runtime, it waits only for the intersection of declared dependencies and actually-created steps. This means convergence works correctly regardless of which path the decision point chose.

Batch processing extends this further — a single batchable step can spawn N worker instances at runtime, all created transactionally, all converging through the same intersection semantics. The graph is not just branching dynamically; it is *scaling* dynamically.

These are not theoretical capabilities. They are implemented, tested, and approaching production readiness in v0.1.2.

---

## The Vision: What If the Planner Were an LLM?

Today, decision point handlers contain business logic written by engineers. The decision is deterministic: if the amount is under $1,000, auto-approve; if over $5,000, require dual approval. The handler returns `CreateSteps { step_names }` where those names are drawn from a template that was designed at development time.

But the machinery doesn't care *how* the decision was made. It cares that the decision produced valid step names, that those steps have registered handlers, and that the resulting graph is acyclic. The decision point is a contract: given context, return a plan. The execution layer validates and materializes that plan with the same transactional guarantees regardless of whether the plan came from a `match` statement or a language model.

This is the vision: **an LLM acting as a workflow planner within Tasker's deterministic execution framework**.

Not an autonomous agent. Not an uncontrolled system making arbitrary decisions. A planner — constrained by a capability schema, bounded by resource limits, validated before execution, observable throughout — that determines the topology of a workflow graph while the system guarantees the execution.

The LLM is stochastic. The step is deterministic. If the LLM's role is constrained to *planning* — generating graph topology and parameterizing steps — while execution remains within Tasker's guarantees, the result is something genuinely novel: probabilistic planning with deterministic execution.

---

## Building From Existing Affordances

This vision does not require a new system. It requires extending affordances that already exist:

**Decision Point Steps → Planning Steps.** A planning step is a decision handler backed by an LLM instead of business logic. It receives the task context (including accumulated results from prior steps) and a capability schema describing what handlers are available. It returns a workflow fragment — a set of steps, their dependencies, their handler configurations — that the orchestration layer validates and materializes through the same transactional creation path that conditional workflows already use.

**Step Templates → Handler Catalog.** Today, step handlers are application-specific code registered in each worker. A handler catalog is a library of generic, parameterized step handlers — HTTP request, data transformation, validation, fan-out, aggregation, notification, gating — that can be composed without writing new code. The LLM plans in terms of capabilities ("fetch this data, validate against this schema, transform into this shape"), and the catalog provides the handlers that execute those capabilities.

**Namespace Queues → Catalog Workers.** Today, workers subscribe to namespace queues based on their registered templates. A catalog worker is a worker deployment that ships with all standard catalog handlers pre-registered, listening on a dedicated namespace. Dynamically planned steps that reference catalog handlers route to these workers through the existing queue infrastructure.

**Deferred Convergence → Recursive Planning.** Today, convergence steps aggregate results from dynamic branches. In the planning model, a convergence step can itself be a planning step — one that receives the accumulated results of the previous phase and plans the next phase of work. The LLM doesn't have to plan the entire solution upfront. It can plan a reconnaissance phase, observe the results, and then plan the execution phase with the benefit of what it learned.

**Batch Processing → Dynamic Scale.** The LLM planner can generate batchable steps, using the same cursor-based fan-out semantics that already exist. If the planner determines that a dataset needs parallel processing, it specifies a batchable step with a worker template, and the existing batch infrastructure handles decomposition, parallel execution, and convergence.

Each of these extensions builds on proven, tested machinery. The novelty is in the composition, not in the individual components.

---

## What This Is Not

Precision matters when describing what AI integration means within an engineering system. This vision is specifically *not* the following:

**It is not autonomous agents.** The LLM does not have persistent state, does not decide when to act, and does not operate outside the boundaries of the workflow system. Every step it plans goes through the same lifecycle, gets the same retry semantics, produces the same observability data as any other step. The system is always in control.

**It is not code generation.** The LLM does not write handlers. It *selects and parameterizes* handlers from a known catalog. There is no hot-loading of generated code, no runtime compilation, no eval. The security boundary is configuration, not execution.

**It is not unconstrained.** Planning steps operate within explicit bounds: maximum graph depth, maximum step count, maximum cost budget, required convergence points. The orchestration layer validates every workflow fragment before materializing it. Invalid plans are rejected, not executed.

**It is not opaque.** Every planning decision is captured — the LLM's reasoning, the generated workflow fragment, the validation result, the materialized steps. The observability guarantees that apply to every Tasker step apply equally to dynamically planned steps. The provenance of every step is traceable to the planning decision that created it.

---

## The Intentional Partnership

This vision is a natural expression of the Intentional AI Partnership philosophy that guides Tasker's development.

The core insight of that philosophy — that AI amplifies existing engineering practices rather than replacing them — applies directly here. Tasker's execution guarantees (determinism, idempotency, transactional consistency, observability) are the engineering practices being amplified. The LLM adds flexibility and reasoning capability to workflow planning without undermining the properties that make the system trustworthy.

The principle of *specification before implementation* maps to the planning step's contract: the LLM produces a specification (the workflow fragment) that the system validates before implementing (materializing and executing). The principle of *human accountability as the final gate* maps to the gate handler — a catalog primitive that allows human approval at any decision point. The principle of *validation as a first-class concern* maps to the fragment validation pipeline that sits between planning and execution.

This is what intentional partnership looks like at the systems level: the AI contributes its strengths (pattern recognition, problem decomposition, reasoning about complex workflows) while the system contributes its strengths (determinism, observability, resilience, accountability). Neither is asked to do what the other does better. The boundaries are clean, the contracts are explicit, and the guarantees are preserved.

---

## Where This Leads

The immediate practical implication is a system where problems can be described in terms of *what needs to happen* rather than *exactly how it should be orchestrated*. An engineer (or another system) describes a goal: "process this dataset, validate each record against these rules, enrich the valid records from this API, route failures to this review queue." The LLM planner decomposes that goal into a workflow graph using the handler catalog, and the system executes it with full deterministic guarantees.

The longer-term implication is recursive problem-solving: multi-phase workflows where each phase's plan is informed by the results of previous phases. Reconnaissance, analysis, execution, validation — each phase planned dynamically based on what was learned, converging toward a goal rather than following a static path.

This does not replace engineering. It changes what engineers spend their time on. Instead of manually decomposing every workflow into steps and templates, engineers invest in the handler catalog (the vocabulary), the capability schemas (the grammar), the resource bounds (the guardrails), and the observability framework (the accountability). The LLM composes within those constraints. The system executes within its guarantees.

The foundation is built. The machinery works. The extension is natural.

---

*This document is part of the Tasker Core dynamic workflow planning initiative. It describes a vision that will be realized through phased implementation, beginning with the handler catalog and progressing through planning interfaces, sandboxed execution, and recursive planning capabilities.*
