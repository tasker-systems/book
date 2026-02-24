# Technical Approach: Action Grammars, Handler Composition, and Agent Integration

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

### Constraint 4: Complex Decisions Require Complete Context

When a planning entity — whether an LLM planning step or a human architect — needs to design a workflow for a complex problem, it must reason about the entire problem in a single pass. There is no mechanism for a planner to *investigate* before deciding — to fan out research, gather information from multiple sources, and converge findings before committing to a workflow design. The planner must hold everything in context at once, which limits the complexity of problems that can be addressed dynamically.

### The Opportunity

These constraints are not bugs. They are consequences of a system designed for reliability and predictability. But they also represent a ceiling on what the system can express.

If we could introduce a vocabulary of composable, type-safe action primitives — and a planner capable of composing them into workflow topologies at runtime — while preserving all of Tasker's execution guarantees, we would unlock a new class of workflows: ones where the *goal* is specified and the *path* is determined at runtime, composed from primitives the system guarantees are correct.

If we could additionally provide agents with the ability to use Tasker's own infrastructure for investigation and context decomposition — creating research workflows whose results inform design decisions — we would address the fundamental limitation of single-pass planning: the requirement that the planner already knows enough to plan well.

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

**Description:** Introduce a layer of composable, Rust-native action grammar primitives with compile-time enforced data contracts. All handler composition — whether referencing a common pattern or assembled dynamically — uses the same `action(resource)` grammar model, validated through the same pipeline at assembly time. Extend the decision point mechanism to support *workflow fragment generation* — a planning step backed by an LLM that composes workflow fragments from the grammar's vocabulary. The orchestration layer validates and materializes these fragments using existing transactional infrastructure. The single-mutation boundary (at most one external mutation after all fallible preparatory work) is the central safety invariant for all compositions.

**Strengths:**

- Builds on proven conditional workflow machinery
- Preserves all execution guarantees (transactionality, idempotency, observability)
- No code generation or hot-loading — only composition of verified primitives
- Primitives are compile-time verified Rust; compositions are validated at assembly time against structural invariants (contract compatibility, single-mutation boundary)
- LLM composes from a vocabulary it cannot break — the type system prevents invalid compositions
- One composition model — common patterns and dynamic compositions use the same grammar and validation pipeline
- Enables recursive planning through nested planning steps
- Action grammars and common patterns are independently valuable even without LLM integration
- Polyglot developers consume action grammars through FFI without needing to understand Rust

**Weaknesses:**

- Requires new infrastructure: action grammar primitives, data contracts, composition framework, fragment validation, capability schemas
- Action grammar design requires careful research into which primitives are fundamental
- LLM planning quality depends on capability schema design
- Assembly-time validation is strong but not compile-time — requires careful design of the validation pipeline
- New observability requirements for dynamically generated workflows
- FFI boundary between Rust grammar layer and polyglot developer layer needs careful design

**Assessment:** This is the approach that fully realizes the opportunity while building on Tasker's existing architecture. The action grammar layer provides strong guarantees through compile-time verified primitives and assembly-time validated compositions. Common patterns provide named, well-tested composition specifications for frequently used combinations, while dynamic composition enables open-ended use of the same grammar. The phased path (TAS-280 → MCP server → action grammars → planning) allows each component to inform the next.

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

**Assessment:** This is a different product. Tasker's strength is deterministic orchestration; an agent framework would require abandoning the properties that make the system trustworthy. **Explicitly rejected.** However, this rejection is specific: what's rejected is Tasker *becoming* an agent. What's embraced is Approach E.

### Approach E: Agent-Accessible Deterministic Infrastructure (Recommended alongside C)

**Description:** Position Tasker as deterministic infrastructure that agents use as external clients. Agents submit tasks through the standard API, create research workflows to decompose complex decisions, and use Tasker's convergence semantics to aggregate findings before committing to workflow designs. The MCP server provides agents with design-time access to template inspection, grammar vocabulary, and composition validation. Agent-created task hierarchies are traced through `parent_correlation_id`.

**Strengths:**

- Requires no new orchestration machinery — agents use existing APIs and task lifecycle
- Preserves all deterministic execution guarantees (agents are clients, not components)
- Addresses the "single-pass planning" limitation: agents can investigate before deciding
- `parent_correlation_id` provides full observability of agent reasoning chains
- Same resource controls (budgets, timeouts, max steps) apply to agent-created tasks
- Composes naturally with Approach C: agents can create tasks that contain planning steps, compose handlers from grammar primitives, and reference common patterns
- The MCP server (Phase 0) is the natural agent integration point — no additional infrastructure needed
- Bounded delegation: agents can create related tasks with explicit resource limits

**Weaknesses:**

- Agents must understand Tasker's task/template model to create effective research workflows
- Research workflow patterns and templates need to be designed and provided
- Agent coordination logic lives outside Tasker, which means agent-side failures are not Tasker-observable
- Patterns for "agent creates a task, waits for results, makes a decision" need standardization

**Assessment:** This approach complements Approach C by addressing the context decomposition problem that Approach C's planning interface cannot solve alone. A planning step within a workflow can compose from action grammar primitives, but it cannot investigate unknowns — it can only reason about the context it receives. An agent operating as an external client *can* investigate, using Tasker's own infrastructure to structure that investigation, and then provide richer context to planning steps or design complete workflows from its findings.

---

## Recommendation

**Proceed with Approach C (Action Grammar with Handler Composition) and Approach E (Agent-Accessible Infrastructure)**, implemented through four phases with a pragmatic "from here to there" path where each phase delivers independent value. Approach E is not a separate phase — it is a cross-cutting capability that becomes richer at each phase.

The key architectural decisions within this approach:

1. **Action grammars as the compositional foundation.** Rust-native primitives (acquire, transform, validate, gate, emit, decide, fan-out, aggregate) with compile-time enforced input/output contracts. The type system guarantees that primitives are correct — if it compiles, the data flow is sound.

2. **One composition model.** All handler composition uses the same `action(resource)` grammar. Common patterns are named, documented, well-tested composition specifications that resolve to standard grammar compositions at execution time — they are a documentation and convenience layer, not a separate runtime concept. Dynamic compositions use the same grammar and validation pipeline. Both execute with identical lifecycle guarantees.

3. **Workflow fragments as the planning output.** The LLM planner returns a structured workflow fragment (steps, dependencies, grammar compositions, input mappings) that the orchestration layer validates against the grammar's structural invariants before materialization. Fragments can reference common patterns, dynamic compositions, or both.

4. **Validation as the trust boundary.** The orchestration layer validates every fragment before materializing it: primitives are compile-time verified Rust; compositions are validated at assembly time against structural invariants (contract compatibility, single-mutation boundary); the DAG is acyclic; input schemas match handler contracts; resource bounds are respected. Invalid fragments are rejected with diagnostic information. The single-mutation boundary — at most one external mutation (Persist, Emit) appearing after all fallible preparatory work — is the central safety invariant.

5. **Two-tier trust model.** Developer-authored handlers (polyglot, FFI, developer-owned) coexist with system-invoked action grammars (Rust-native, compile-time enforced, LLM-composable) in the same workflow. The orchestration layer treats both as steps.

6. **Recursive planning through nested planning steps.** Planning steps can appear at any point in a workflow, including downstream of other planned segments. Each planning step receives accumulated context from prior steps, enabling multi-phase workflows where each phase's plan is informed by previous results.

7. **Agents as external clients.** Agents interact with Tasker through the standard API (task submission) and the MCP server (design-time inspection and validation). Task-level delegation through `parent_correlation_id` provides agent reasoning chain traceability. Research workflow patterns provide reusable templates for agent-driven investigation.

8. **Shared tooling foundation.** The `tasker-tooling` crate provides the shared logic consumed by both `tasker-ctl` (CLI interface) and `tasker-mcp` (MCP server / agent interface), ensuring consistent behavior across human and machine interaction surfaces.

---

## Phases of Implementation

### Phase 0: Foundation — Templates as Generative Contracts

**Goal:** Establish the tooling foundation through typed code generation (TAS-280), an MCP server for LLM-assisted workflow authoring, and the shared tooling crate.

**Deliverables:**

- `result_schema` on TaskTemplate step definitions with typed code generation in all four languages
- MCP server for template validation, handler resolution checking, and template/handler generation
- `tasker-tooling` crate extracting shared logic between `tasker-ctl` and `tasker-mcp`
- Patterns and insights that inform action grammar design

**Validation Gate:** `tasker-ctl generate` produces typed handler scaffolds. MCP server generates valid templates from natural language descriptions. Schema compatibility between connected steps is validated. Agent clients can use the MCP server for template inspection and validation.

**Dependencies:** None — builds on existing TaskTemplate infrastructure and TAS-280.

### Phase 1: Action Grammars and Handler Composition

**Goal:** Establish the vocabulary of composable, type-safe action primitives and the unified composition model for building handlers from them.

**Deliverables:**

- Action grammar primitive framework in Rust with compile-time data contracts
- Core primitives: acquire, transform, validate, gate, emit, decide, fan-out, aggregate
- Common patterns: named, documented, well-tested composition specifications for frequently used combinations
- Composition validation framework enforcing structural invariants (contract compatibility, single-mutation boundary)
- Capability schema format derived from grammar composition
- FFI surface for polyglot developer consumption
- Grammar worker deployment configuration

**Validation Gate:** Handlers composed from grammar primitives execute through the grammar worker. Common patterns and dynamic compositions pass the same assembly-time validation and execute correctly. Primitives are compile-time verified Rust; compositions are validated at assembly time against structural invariants. Polyglot developers can use grammar-composed handlers through FFI.

**Dependencies:** Phase 0 informs grammar design through observed patterns.

### Phase 2: Planning Interface

**Goal:** Enable LLM-backed planning steps that generate workflow fragments composed from action grammar primitives.

**Deliverables:**

- Workflow fragment schema (steps, dependencies, grammar compositions, input mappings)
- Fragment validation pipeline (structural invariant checking, DAG validation, resource bound checking)
- Planning step handler type
- LLM integration adapter (configurable model selection, prompt construction from capability schema)
- Fragment materialization service

**Validation Gate:** An LLM-backed planning step generates a valid workflow fragment from a problem description, that fragment is validated (including grammar composition structural invariant checking) and executed through standard Tasker infrastructure. Agent-created tasks containing planning steps execute correctly with full traceability through `parent_correlation_id`.

**Dependencies:** Phase 1 (action grammar provides the vocabulary that fragments reference).

### Phase 3: Recursive Planning and Adaptive Workflows

**Goal:** Enable multi-phase workflows where each phase's plan is informed by previous results, and agent-driven task-level delegation for investigation workflows.

**Deliverables:**

- Nested planning step support
- Context accumulation patterns (with typed data contracts aiding summarization)
- Planning depth and breadth controls
- Cost tracking and budgeting
- Adaptive convergence patterns
- Research workflow templates and patterns for agent-driven investigation
- Agent delegation patterns with bounded resource allocation

**Validation Gate:** A multi-phase workflow can plan, execute, observe results, and re-plan for subsequent phases. Agent-created research tasks converge and deliver structured results for downstream planning. Resource bounds are enforced and the system terminates gracefully when bounds are exceeded.

**Dependencies:** Phase 1 + Phase 2. Phase 3 should be informed by operational experience with Phase 2.

---

## Risk Assessment

| Risk | Severity | Likelihood | Mitigation |
|------|----------|------------|------------|
| Action grammar primitives too coarse or too fine | High | Medium | Phase 0's MCP server and TAS-280 experience reveals actual patterns. Start with coarse primitives; refine based on observed composition needs. |
| LLM generates invalid workflow fragments | Medium | High | Fragment validation pipeline rejects invalid plans before execution. Grammar type system prevents invalid compositions. This is expected behavior, not a failure mode. |
| Composition validation insufficient for edge cases | Medium | Medium | Assembly-time validation catches structural mismatches. The single-mutation boundary provides a strong structural invariant. Operational experience identifies additional validation rules. Frequently used compositions become common patterns with additional testing. |
| Common patterns insufficient for real workflows | High | Medium | Common patterns are extensible. Dynamic composition from grammar primitives fills gaps without code changes. Organization-specific compositions supplement the standard set. Developer-authored handlers coexist with grammar-composed handlers in the same workflow. |
| Rust-to-polyglot FFI boundary too complex | Medium | Medium | Phase 0's MCP server and code generation establish the pattern. Polyglot developers consume through configuration and their language's DSL, not raw FFI. |
| LLM planning quality too low for useful workflows | High | Low-Medium | Capability schema design (derived from grammar composition) is the primary lever. MCP server experience from Phase 0 informs prompt engineering. |
| Recursive planning creates runaway graphs | High | Medium | Resource bounds enforced at the orchestration level: max depth, max total steps, cost budgets. Planning steps that exceed bounds fail cleanly with diagnostic information. |
| Agent-created task chains become unmanageable | Medium | Medium | Resource bounds on agent-created tasks. `parent_correlation_id` provides chain traceability. Research workflow templates provide bounded, well-designed patterns. |
| Data contract evolution breaks existing compositions | Medium | Medium | Schema versioning strategy. Grammar primitives are additive; existing compositions remain valid as new primitives are added. |
| Shared tooling crate creates coupling | Low | Medium | `tasker-tooling` exposes stable interfaces. CLI and MCP server consume through the interface, not implementation details. Premature extraction is the real risk — extract when the API surface stabilizes. |

---

## Timeline Considerations

Phase 0 (Foundation) is immediately actionable. TAS-280 is already specified. The MCP server can begin prototyping alongside it. The `tasker-tooling` extraction should follow once TAS-280 stabilizes the codegen and validation APIs. All deliver independent value and require no orchestration runtime changes.

Phase 1 (Action Grammars) is the core architectural investment. It should begin as Phase 0's patterns inform the grammar design. This is where the most design research is needed — establishing the primitives, the composition model, and the structural invariants (especially the single-mutation boundary) that all compositions must satisfy.

Phase 2 (Planning Interface) requires Phase 1 and is the heart of the generative vision. MCP server experience from Phase 0 significantly de-risks the LLM integration design. Agent integration through the MCP server and standard API is available from Phase 0 onward and becomes more capable as each phase adds vocabulary.

Phase 3 (Recursive Planning) requires Phase 2 and represents the full realization of the vision. It is the most speculative phase and should be informed by operational experience with Phase 2. Agent-driven research workflow patterns can be developed in parallel with Phase 2, informed by Phase 0 and Phase 1 experience.

**WASM sandboxing** is a valuable capability that can be pursued as a parallel effort at any point. It complements grammar-composed handlers by providing execution isolation for compositions, but is not a prerequisite for any phase of this initiative.

---

*Each phase is elaborated in its own document with detailed research areas, design questions, prototyping goals, and validation criteria. The agent integration capability is described in a dedicated cross-cutting document rather than a phase-specific document, as it composes with all phases.*
