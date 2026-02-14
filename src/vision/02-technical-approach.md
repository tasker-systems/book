# Dynamic Workflow Planning: Technical Approach

*Problem Statement, Solution Consideration, Recommendation, and Phases of Implementation*

---

## Problem Statement

Tasker Core provides deterministic workflow orchestration with conditional branching, batch processing, and convergence semantics. These capabilities are powerful but require workflows to be fully designed at development time: every step must have a registered handler, every decision path must be anticipated in a template, every handler must be implemented in application code.

This creates three constraints that limit the system's expressiveness:

### Constraint 1: Decision Logic is Static

Decision point handlers evaluate business rules and return step names from a pre-declared template. The decision space is bounded by what was anticipated when the template was authored. Unanticipated scenarios — novel data shapes, unforeseen combinations of conditions, problems that require multi-step reasoning to decompose — cannot be handled without authoring new templates and deploying new code.

### Constraint 2: Handlers are Application-Specific

Every step in a workflow requires a handler implemented in application code. There is no shared vocabulary of common operations (HTTP requests, data transformations, schema validations, fan-out patterns) that can be composed without writing new code. This means that even workflows consisting entirely of common operations — fetch data, validate, transform, store — require custom handler implementations.

### Constraint 3: Workflow Topology is Fixed at Template Time

Task templates define the complete set of *possible* steps. While conditional workflows defer step *creation* to runtime, the universe of creatable steps is fixed. There is no mechanism for generating workflow topology that wasn't anticipated in the template — no way to say "use whatever steps are needed to solve this problem."

### The Opportunity

These constraints are not bugs. They are consequences of a system designed for reliability and predictability. But they also represent a ceiling on what the system can express.

If we could introduce a planner capable of reasoning about problems and generating workflow topologies from a known set of composable capabilities — while preserving all of Tasker's execution guarantees — we would unlock a new class of workflows: ones where the *goal* is specified and the *path* is determined at runtime.

---

## Solution Consideration

### Approach A: LLM as External Advisor

**Description:** An LLM operates outside Tasker, generating complete task templates (YAML) that are then submitted through normal task creation flows.

**Strengths:**

- No changes to Tasker's internals
- Clean separation between planning and execution
- Template validation catches errors before execution

**Weaknesses:**

- No iterative planning — the entire workflow must be known upfront
- No access to intermediate results for adaptive planning
- Requires full template + handler deployment before execution
- Loses the dynamic branching capabilities Tasker already has

**Assessment:** This is already possible today and is valuable as a developer productivity tool. It does not address the core opportunity of runtime adaptive planning.

### Approach B: LLM as Decision Handler (Current Architecture)

**Description:** An LLM serves as the business logic behind a decision point handler, choosing from pre-declared step names in an existing template.

**Strengths:**

- Works within current architecture with no modifications
- LLM adds reasoning to existing decision points
- All execution guarantees preserved

**Weaknesses:**

- Decision space still bounded by template-declared steps
- LLM cannot generate novel workflow topology
- Handlers must still be application-specific code
- No composition of generic capabilities

**Assessment:** Valuable and achievable immediately. Should be demonstrated in `tasker-contrib` as a pattern. But it is an incremental improvement, not a paradigm extension.

### Approach C: LLM as Workflow Planner with Handler Catalog (Recommended)

**Description:** Extend the decision point mechanism to support *workflow fragment generation* — a planning step backed by an LLM that generates not just step names but complete step configurations drawn from a catalog of generic, parameterized handlers. The orchestration layer validates and materializes these fragments using existing transactional infrastructure.

**Strengths:**

- Builds on proven conditional workflow machinery
- Preserves all execution guarantees (transactionality, idempotency, observability)
- No code generation or hot-loading — only configuration of known handlers
- Enables recursive planning through nested planning steps
- Handler catalog is independently valuable even without LLM integration
- WASM sandboxing provides security boundary for catalog execution

**Weaknesses:**

- Requires new infrastructure: handler catalog, fragment validation, capability schemas
- WASM broker depends on ecosystem maturity (mitigated by phased approach)
- LLM planning quality depends on capability schema design
- New observability requirements for dynamically generated workflows

**Assessment:** This is the approach that fully realizes the opportunity while building on Tasker's existing architecture. Each component is independently valuable, the phases can be delivered incrementally, and the risk is managed through clear validation boundaries.

### Approach D: Full Agent Framework

**Description:** Build a general-purpose AI agent framework within Tasker, with persistent memory, autonomous decision-making, and dynamic tool selection.

**Strengths:**

- Maximum flexibility
- Aligns with industry "agent" narrative

**Weaknesses:**

- Undermines Tasker's core value proposition (determinism, predictability)
- Enormous complexity with unclear boundaries
- Agent failure modes are poorly understood
- Observability becomes intractable
- Fundamentally different system with different guarantees

**Assessment:** This is a different product. Tasker's strength is deterministic orchestration; an agent framework would require abandoning the properties that make the system trustworthy. Explicitly rejected.

---

## Recommendation

**Proceed with Approach C: LLM as Workflow Planner with Handler Catalog**, implemented through four phases with clear validation gates between each.

The key architectural decisions within this approach:

1. **Handler catalog as the vocabulary.** Generic, parameterized step handlers that execute common operations (HTTP, transform, validate, fan-out, aggregate, gate, notify) without custom code. These handlers are independently valuable and should be developed in `tasker-contrib`.

2. **Workflow fragments as the planning output.** The LLM planner does not return step names — it returns a structured workflow fragment (steps, dependencies, handler configurations, input mappings) that the orchestration layer validates against the handler catalog's capability schema before materialization.

3. **Validation as the trust boundary.** The orchestration layer validates every fragment before materializing it: handler references exist in the catalog, the DAG is acyclic, input schemas match handler contracts, resource bounds are respected. Invalid fragments are rejected with diagnostic information.

4. **WASM broker as the execution boundary.** Catalog handlers compiled to WASM execute in sandboxed environments. The broker is a Tasker worker from the orchestration layer's perspective — it subscribes to a namespace queue and processes steps — but internally it instantiates WASM modules with controlled host function access.

5. **Recursive planning through nested planning steps.** Planning steps can appear at any point in a workflow, including downstream of other planned segments. Each planning step receives accumulated context from prior steps, enabling multi-phase workflows where each phase's plan is informed by previous results.

---

## Phases of Implementation

### Phase 1: Handler Catalog

**Goal:** Establish the vocabulary of composable step handlers.

**Deliverables:**

- Generic handler framework in `tasker-contrib` with parameterized configuration
- Core catalog handlers: `http_request`, `transform`, `validate`, `fan_out`, `aggregate`, `gate`, `notify`, `decide`
- Capability schema format (machine-readable descriptions of handler inputs, outputs, and behavior)
- Catalog worker deployment configuration
- Documentation and examples

**Validation Gate:** Catalog handlers can be used in manually-authored task templates, executing through standard Tasker workers. No LLM integration required — the catalog is independently valuable.

**Dependencies:** None — builds on existing handler registration and step execution infrastructure.

### Phase 2: Planning Interface

**Goal:** Enable LLM-backed planning steps that generate workflow fragments.

**Deliverables:**

- Workflow fragment schema (structured representation of steps, dependencies, configurations)
- Fragment validation pipeline (DAG validation, handler reference checking, schema validation, resource bound checking)
- Planning step handler type (decision handler extension that returns fragments instead of step names)
- LLM integration adapter (configurable model selection, prompt construction from capability schema and task context)
- Fragment materialization service (extends existing dynamic step creation)

**Validation Gate:** An LLM-backed planning step can generate a valid workflow fragment from a problem description, and that fragment is validated and executed through standard Tasker infrastructure. Human-authored tests confirm correct fragment validation (acceptance and rejection).

**Dependencies:** Phase 1 (handler catalog provides the handlers that fragments reference).

### Phase 3: Sandboxed Execution via WASM Broker

**Goal:** Provide a security and isolation boundary for catalog handler execution.

**Deliverables:**

- WASM compilation targets for catalog handlers
- WASM broker worker (Wasmtime-based host that instantiates handler modules)
- Host function interface (HTTP, logging, input/output — no direct database access)
- Broker-level resource controls (memory limits, execution timeouts, I/O budgets)
- Performance benchmarking (cold start, throughput, comparison with FFI workers)

**Validation Gate:** Catalog handlers execute in WASM sandboxes with equivalent correctness to native execution. Security boundary prevents handlers from accessing resources not explicitly granted through host functions.

**Dependencies:** Phase 1 (catalog handlers are what gets compiled to WASM). Independent of Phase 2 — the WASM broker benefits all catalog handler usage, not just LLM-planned workflows.

### Phase 4: Recursive Planning and Adaptive Workflows

**Goal:** Enable multi-phase workflows where each phase's plan is informed by previous results.

**Deliverables:**

- Nested planning step support (planning steps downstream of other planned segments)
- Context accumulation patterns (how results from prior phases flow into subsequent planning steps)
- Planning depth and breadth controls (resource bounds on recursive planning)
- Cost tracking and budgeting (aggregate cost across planning phases)
- Adaptive convergence patterns (planning steps that determine their own convergence criteria)

**Validation Gate:** A multi-phase workflow can plan, execute, observe results, and re-plan for subsequent phases. Resource bounds are enforced and the system terminates gracefully when bounds are exceeded.

**Dependencies:** Phase 1 + Phase 2. Phase 3 is recommended but not strictly required (catalog handlers can execute through native workers without WASM sandboxing).

---

## Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| LLM generates invalid workflow fragments | Medium | High | Fragment validation pipeline rejects invalid plans before execution. This is expected behavior, not a failure mode. |
| Handler catalog insufficient for real workflows | High | Medium | Design catalog as extensible; organization-specific handlers supplement but don't replace the standard set. Progressive enrichment based on observed planning patterns. |
| WASM ecosystem not mature enough for Phase 3 | Medium | Medium | Phase 3 is independent and can be deferred. Catalog handlers execute through native workers in the interim. Monitor WASI 0.3+ stabilization. |
| LLM planning quality too low for useful workflows | High | Low-Medium | Capability schema design is the primary lever. Investment in schema quality, planning prompts, and few-shot examples. Fallback to manually-authored workflows for critical paths. |
| Recursive planning creates runaway graphs | High | Medium | Resource bounds enforced at the orchestration level: max depth, max total steps, cost budgets. Planning steps that exceed bounds fail cleanly with diagnostic information. |
| Observability overwhelmed by dynamic workflows | Medium | Medium | Phase-specific observability design (see Complexity Management document). Planning provenance, fragment lineage, and aggregated metrics designed alongside execution infrastructure. |

---

## Timeline Considerations

Phase 1 (Handler Catalog) is the foundation and should begin immediately. It delivers independent value — composable handlers improve the developer experience for all Tasker users, not just those using LLM planning — and establishes the vocabulary that all subsequent phases depend on.

Phase 2 (Planning Interface) requires Phase 1 and is the core of the vision. It should begin as soon as the initial catalog handlers are functional.

Phase 3 (WASM Broker) is architecturally independent and tracks external ecosystem maturity. It can be pursued in parallel with Phase 2 or deferred based on WASI progress.

Phase 4 (Recursive Planning) requires Phase 2 and represents the full realization of the vision. It is also the phase with the most open design questions and should be informed by operational experience with Phase 2.

---

*Each phase is elaborated in its own document with detailed research areas, design questions, prototyping goals, and validation criteria.*
