# Technical Approach: Action Grammars and Composable Handlers

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

If we could introduce a vocabulary of composable, type-safe action primitives — and a planner capable of composing them into workflow topologies at runtime — while preserving all of Tasker's execution guarantees, we would unlock a new class of workflows: ones where the *goal* is specified and the *path* is determined at runtime, composed from primitives the system guarantees are correct.

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

**Assessment:** This is already possible today and is valuable as a developer productivity tool. It does not address the core opportunity of runtime adaptive planning. Phase 0's MCP server pursues this path for its immediate developer experience value.

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

### Approach C: LLM as Workflow Planner with Action Grammar (Recommended)

**Description:** Introduce a layer of composable, Rust-native action grammar primitives with compile-time enforced data contracts. Build a handler catalog from compositions of these primitives. Extend the decision point mechanism to support *workflow fragment generation* — a planning step backed by an LLM that composes workflow fragments from the grammar's vocabulary. The orchestration layer validates and materializes these fragments using existing transactional infrastructure.

**Strengths:**

- Builds on proven conditional workflow machinery
- Preserves all execution guarantees (transactionality, idempotency, observability)
- No code generation or hot-loading — only composition of verified primitives
- Compile-time enforcement of data contracts between primitives makes composition provably correct
- LLM composes from a vocabulary it cannot break — the type system prevents invalid compositions
- Enables recursive planning through nested planning steps
- Handler catalog and action grammars are independently valuable even without LLM integration
- Polyglot developers consume action grammars through FFI without needing to understand Rust

**Weaknesses:**

- Requires new infrastructure: action grammar primitives, data contracts, composition framework, fragment validation, capability schemas
- Action grammar design requires careful research into which primitives are fundamental
- LLM planning quality depends on capability schema design
- New observability requirements for dynamically generated workflows
- FFI boundary between Rust grammar layer and polyglot developer layer needs careful design

**Assessment:** This is the approach that fully realizes the opportunity while building on Tasker's existing architecture. The action grammar layer provides stronger guarantees than a flat handler catalog, and the phased path (TAS-280 → MCP server → action grammars → planning) allows each component to inform the next.

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

**Proceed with Approach C: LLM as Workflow Planner with Action Grammar**, implemented through four phases with a pragmatic "from here to there" path where each phase delivers independent value.

The key architectural decisions within this approach:

1. **Action grammars as the compositional foundation.** Rust-native primitives (acquire, transform, validate, gate, emit, decide, fan-out, aggregate) with compile-time enforced input/output contracts. The type system guarantees that compositions are correct — if it compiles, the data flow is sound.

2. **Handler catalog as composed vocabulary.** The catalog is a library of pre-composed handlers built from action grammar primitives, not a flat collection of independent implementations. Capability schemas are derived from grammar composition rather than hand-authored, giving the LLM planner an accurate and consistent vocabulary.

3. **Workflow fragments as the planning output.** The LLM planner returns a structured workflow fragment (steps, dependencies, grammar compositions, input mappings) that the orchestration layer validates against the grammar's type constraints before materialization.

4. **Validation as the trust boundary.** The orchestration layer validates every fragment before materializing it: grammar compositions are type-checked, the DAG is acyclic, input schemas match handler contracts, resource bounds are respected. Invalid fragments are rejected with diagnostic information.

5. **Two-tier trust model.** Developer-authored handlers (polyglot, FFI, developer-owned) coexist with system-invoked action grammars (Rust-native, compile-time enforced, LLM-composable) in the same workflow. The orchestration layer treats both as steps.

6. **Recursive planning through nested planning steps.** Planning steps can appear at any point in a workflow, including downstream of other planned segments. Each planning step receives accumulated context from prior steps, enabling multi-phase workflows where each phase's plan is informed by previous results.

---

## Phases of Implementation

### Phase 0: Foundation — Templates as Generative Contracts

**Goal:** Establish the tooling foundation through typed code generation (TAS-280) and an MCP server for LLM-assisted workflow authoring.

**Deliverables:**

- `result_schema` on TaskTemplate step definitions with typed code generation in all four languages
- MCP server for template validation, handler resolution checking, and template/handler generation
- Patterns and insights that inform action grammar design

**Validation Gate:** `tasker-ctl generate` produces typed handler scaffolds. MCP server generates valid templates from natural language descriptions. Schema compatibility between connected steps is validated.

**Dependencies:** None — builds on existing TaskTemplate infrastructure and TAS-280.

### Phase 1: Action Grammars and Handler Catalog

**Goal:** Establish the vocabulary of composable, type-safe action primitives and the handler catalog built from them.

**Deliverables:**

- Action grammar primitive framework in Rust with compile-time data contracts
- Core primitives: acquire, transform, validate, gate, emit, decide, fan-out, aggregate
- Handler catalog: pre-composed handlers built from grammar primitives
- Capability schema format derived from grammar composition
- FFI surface for polyglot developer consumption
- Catalog worker deployment configuration

**Validation Gate:** Catalog handlers composed from grammar primitives can be used in manually-authored task templates, executing through standard Tasker workers. Grammar compositions are type-checked at compile time. Polyglot developers can use catalog handlers through FFI.

**Dependencies:** Phase 0 informs grammar design through observed patterns.

### Phase 2: Planning Interface

**Goal:** Enable LLM-backed planning steps that generate workflow fragments composed from action grammar primitives.

**Deliverables:**

- Workflow fragment schema (steps, dependencies, grammar compositions, input mappings)
- Fragment validation pipeline (type checking, DAG validation, resource bound checking)
- Planning step handler type
- LLM integration adapter (configurable model selection, prompt construction from capability schema)
- Fragment materialization service

**Validation Gate:** An LLM-backed planning step generates a valid workflow fragment from a problem description, that fragment is validated (including grammar composition type checking) and executed through standard Tasker infrastructure.

**Dependencies:** Phase 1 (action grammar provides the vocabulary that fragments reference).

### Phase 3: Recursive Planning and Adaptive Workflows

**Goal:** Enable multi-phase workflows where each phase's plan is informed by previous results.

**Deliverables:**

- Nested planning step support
- Context accumulation patterns (with typed data contracts aiding summarization)
- Planning depth and breadth controls
- Cost tracking and budgeting
- Adaptive convergence patterns

**Validation Gate:** A multi-phase workflow can plan, execute, observe results, and re-plan for subsequent phases. Resource bounds are enforced and the system terminates gracefully when bounds are exceeded.

**Dependencies:** Phase 1 + Phase 2. Phase 3 should be informed by operational experience with Phase 2.

---

## Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Action grammar primitives too coarse or too fine | High | Medium | Phase 0's MCP server and TAS-280 experience reveals actual patterns. Start with coarse primitives; refine based on observed composition needs. |
| LLM generates invalid workflow fragments | Medium | High | Fragment validation pipeline rejects invalid plans before execution. Grammar type system prevents invalid compositions. This is expected behavior, not a failure mode. |
| Handler catalog insufficient for real workflows | High | Medium | Catalog is extensible. Organization-specific handlers supplement the standard set. Developer-authored handlers coexist with catalog handlers in the same workflow. |
| Rust-to-polyglot FFI boundary too complex | Medium | Medium | Phase 0's MCP server and code generation establish the pattern. Polyglot developers consume through configuration and their language's DSL, not raw FFI. |
| LLM planning quality too low for useful workflows | High | Low-Medium | Capability schema design (derived from grammar composition) is the primary lever. MCP server experience from Phase 0 informs prompt engineering. |
| Recursive planning creates runaway graphs | High | Medium | Resource bounds enforced at the orchestration level: max depth, max total steps, cost budgets. Planning steps that exceed bounds fail cleanly with diagnostic information. |
| Data contract evolution breaks existing compositions | Medium | Medium | Schema versioning strategy. Grammar primitives are additive; existing compositions remain valid as new primitives are added. |

---

## Timeline Considerations

Phase 0 (Foundation) is immediately actionable. TAS-280 is already specified. The MCP server can begin prototyping alongside it. Both deliver independent value and require no orchestration runtime changes.

Phase 1 (Action Grammars) is the core architectural investment. It should begin as Phase 0's patterns inform the grammar design. This is where the most design research is needed.

Phase 2 (Planning Interface) requires Phase 1 and is the heart of the generative vision. MCP server experience from Phase 0 significantly de-risks the LLM integration design.

Phase 3 (Recursive Planning) requires Phase 2 and represents the full realization of the vision. It is the most speculative phase and should be informed by operational experience with Phase 2.

**WASM sandboxing** is a valuable capability that can be pursued as a parallel effort at any point. It complements the handler catalog by providing execution isolation for grammar compositions, but is not a prerequisite for any phase of this initiative.

---

*Each phase is elaborated in its own document with detailed research areas, design questions, prototyping goals, and validation criteria.*
