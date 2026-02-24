# Managing Complexity in Dynamic Workflow Planning

*Complexity grounded in simplicity, for humans, LLMs, agents, and observability systems — and how structural invariants reduce runtime surprises*

---

## The Distinction: Complexity vs. Complication

Dynamic workflow planning is inherently complex. A system where an LLM generates workflow topology at runtime, where handlers can be composed dynamically from grammar primitives, where agents create investigation task chains, where planning can recur across multiple phases — this introduces combinatorial possibilities that static workflows do not have.

Complexity is not the concern. *Complication* is.

Complexity arises from the genuine richness of a problem space. A workflow that adapts to its inputs, that routes through different processing paths based on data characteristics, that plans in phases informed by intermediate results — this is complex because the problem is complex. The system's behavior reflects the problem's structure.

Complication arises from *incidental* difficulty — difficulty that exists because of how the system was built rather than because of what it does. Configuration that requires understanding internal implementation details. Failure modes that are opaque. Observability that buries the signal in noise. Abstractions that leak. Mental models that don't match system behavior.

The goal of this document is to ensure that dynamic workflow planning introduces complexity proportional to the problems it solves while ruthlessly eliminating complication. The same step — with its state machine, its idempotency, its lifecycle — remains the atomic unit. The same execution guarantees hold. The same observability contracts apply. What's new is the *topology*, not the *mechanics*.

---

## Four Audiences, Four Models

Dynamic workflow planning has four distinct audiences, each with different mental models and different needs. Complexity management must serve all of them.

### 1. Human Operators

Operators need to understand what the system is doing, why it's doing it, and what to do when something goes wrong. For dynamic workflows, this means:

- **What was planned and why.** Every planning step's reasoning, the fragment it generated, and the validation result must be inspectable.
- **What is executing now.** The current state of all active steps, including dynamically created ones (whether referencing common patterns or dynamically composed), must be visible through the same interfaces used for static workflows.
- **What went wrong.** Failures in dynamic workflows must be diagnosable with the same tools used for static workflows, with additional context about the planning decisions that led to the failed step.
- **What is the agent doing.** For agent-created task chains, the `parent_correlation_id` lineage must be traceable, showing the progression from investigation through design to execution.

**The complication trap for operators:** If dynamically planned workflows appear fundamentally different from static workflows in the observability UI — if they require a different mental model, different tooling, different diagnostic procedures — then we have introduced complication. The operator should see steps, dependencies, states, and results. The fact that some steps were created by a planner rather than a template, or composed dynamically rather than referencing a common pattern, should be *visible* but not *disruptive*.

### 2. LLMs as Planners

The LLM planner needs to understand what capabilities are available, what the problem context is, and what constraints apply. For effective planning, this means:

- **Clear capability descriptions.** The action grammar primitives, common patterns, and composition rules must be described in terms the LLM can reason about — not implementation details, but semantic capabilities, input/output contracts, and composition patterns. Because capability schemas are derived from grammar composition types (not hand-authored), they are always accurate.
- **Bounded context.** The information provided to the planner must be sufficient for good decisions but not so voluminous that it degrades reasoning quality. This is a context window management problem with direct impact on planning quality.
- **Structured feedback.** When a plan is invalid, the validation diagnostics must be actionable by the LLM in a retry attempt. "Handler 'foo' not found" is useful. "Validation failed" is not.

**The complication trap for LLMs:** If the capability schema is too granular (every parameter of every handler), the LLM drowns in detail. If it's too abstract ("handlers exist"), the LLM can't plan concretely. If the planning prompt requires understanding of Tasker internals (queue namespaces, transaction boundaries, PGMQ message formats), we've leaked implementation into the planning layer. The LLM should plan in terms of *what needs to happen*, not *how Tasker works*.

### 3. Agents as Clients

Agents need to understand what Tasker can do for them, how to structure their investigation and workflow creation, and how to monitor progress and handle failures. For effective agent integration, this means:

- **Discoverable capabilities.** The MCP server exposes what templates exist, what action grammar primitives are available, what schemas look like, and what resource limits apply. The agent should be able to explore the system's capabilities without prior knowledge.
- **Structured results.** Task completion delivers results in a form the agent can reason about — typed data contracts mean the agent knows the shape of what it's getting back.
- **Clear failure modes.** When a task or step fails, the agent receives structured diagnostic information sufficient to decide on recovery (retry, revise, escalate).
- **Lineage tracking.** The agent's chain of tasks (linked by `parent_correlation_id`) is traceable, enabling the agent — and human operators overseeing the agent — to understand the full investigation arc.

**The complication trap for agents:** If the agent needs to understand Tasker's internal architecture to use it effectively, the abstraction has leaked. The agent should think in terms of "I need to investigate these three things in parallel and then combine the results" — not in terms of PGMQ queues, step state machines, or worker namespaces. The MCP server and task API should present the right level of abstraction.

### 4. Observability Systems

Observability infrastructure needs to ingest, correlate, and present the telemetry from dynamic workflows without special-casing. For coherent observability, this means:

- **Consistent telemetry shape.** Dynamically created steps emit the same metrics, logs, and traces as statically defined steps. Virtual handler steps emit the same telemetry as catalog handler steps. No parallel telemetry pipeline for "dynamic" or "virtual" steps.
- **Planning provenance.** Additional metadata connects each step to the planning decision that created it, enabling drill-down from "what happened" to "why this was planned."
- **Virtual handler provenance.** Steps executed by virtual handlers include the composition specification in their metadata, enabling drill-down from "what failed" to "what composition was attempted."
- **Task lineage.** For agent-created task chains, `parent_correlation_id` enables correlation across tasks, showing the full arc from investigation to execution.
- **Aggregation across dynamic topologies.** When a task template produces workflows with different shapes (because the planner chose different paths), observability must support comparison and aggregation across these variations.

**The complication trap for observability:** If dynamic workflows generate telemetry that existing dashboards and alerts can't consume, operators fall back to log grep. If planning provenance is stored in a different system than step telemetry, correlation requires manual effort. If each unique workflow topology gets its own metric namespace, aggregation becomes impossible.

---

## Design Principles for Complexity Management

### Principle 1: The Step Remains the Atom

Every capability in dynamic workflow planning is expressed through steps. A planning step is a step. A grammar-composed handler step is a step. A convergence step is a step. Each has the same lifecycle, the same state machine, the same observability contract.

The action grammar layer adds compositional depth *within* a step — a handler may be composed from Acquire → Transform → Validate primitives — but from the orchestration layer's perspective, it is still a single step with a single lifecycle. Whether the handler referenced a common pattern or was composed dynamically is an implementation detail of the handler, not a new structural concept in the workflow.

**Implication:** No new top-level concepts. No "planning phase" object separate from steps. No "fragment execution" lifecycle separate from step execution. No "grammar composition" lifecycle visible to the orchestrator. No "agent task" type separate from regular tasks. The DAG is the DAG, whether its topology was determined by a template, a planner, or an agent.

**What this means practically:**

- The workflow visualization shows steps and edges, regardless of how they were created
- Step-level alerts (timeout, failure, retry) work identically for all grammar-composed steps
- The DLQ system processes planned steps the same way as static steps
- Performance metrics (step latency, throughput) aggregate across planned and static steps regardless of composition origin

### Principle 2: Provenance is Metadata, Not Structure

The fact that a step was created by a planning step rather than a template, or composed dynamically rather than referencing a common pattern, is important context. But it should be captured as *metadata on the step*, not as a *structural difference in how the step exists in the system*.

**Implication:** Add provenance fields to the step record, not a parallel provenance system.

**Proposed provenance metadata (stored in `workflow_steps` or related JSONB):**

| Field | Type | Description |
|-------|------|-------------|
| `created_by` | enum | `template` / `decision_point` / `planning_step` / `batch_spawn` |
| `planning_step_uuid` | uuid? | The planning step that created this step (if applicable) |
| `fragment_id` | string? | Identifier of the workflow fragment this step belongs to |
| `planning_phase` | integer? | Which planning phase (1, 2, 3...) this step was created in |
| `planning_reasoning` | text? | The planner's reasoning for including this step |
| `handler_type` | enum | `application` / `grammar` |
| `composition_source` | string? | Whether a grammar handler referenced a common pattern name or was composed dynamically (metadata, not a type distinction) |
| `composition_spec` | jsonb? | The grammar composition specification (if applicable) |

This metadata enriches observability without changing the step's identity. Dashboards can filter by `created_by` to show only planned steps, or by `handler_type` to distinguish developer-authored from grammar-composed steps. Traces can include `planning_step_uuid` for drill-down. But the default view — the one operators see every day — shows steps as steps.

### Principle 3: Progressive Disclosure

Not everyone needs to see everything. The default view should show what's essential: steps, states, results, timing. Planning details, composition specifications, and agent lineage should be available on drill-down, not in the primary display.

**Layer 1: Workflow Overview** (same as static workflows)

- Task status, step states, dependency graph, timing
- Steps created by planners are visually annotated but not structurally different
- Dynamically composed steps are visually annotated but appear as normal steps
- Summary: "This task had 2 planning phases, created 14 steps total (12 grammar, 2 application)"

**Layer 2: Planning Details** (drill into a planning step)

- The planning prompt (what the LLM was asked)
- The capability schema provided (what the LLM could use)
- The generated fragment (what the LLM planned)
- The validation result (accepted/rejected, with diagnostics)
- Token usage, latency, model identifier

**Layer 3: Fragment Analysis** (drill into the fragment)

- The fragment's DAG structure
- Each step's handler configuration (common pattern reference, dynamic composition, or application callable)
- Input mappings and data flow
- Comparison with alternative fragments (if retry occurred)

**Layer 4: Composition Details** (drill into a grammar-composed step)

- The composition specification (which primitives, in what order, with what configuration)
- Whether the composition referenced a common pattern or was dynamically assembled
- Structural invariant validation results (contract compatibility, single-mutation boundary)
- Per-primitive execution details (timing, intermediate results if captured)

**Layer 5: Execution Details** (same as static workflows)

- Individual step execution: inputs, outputs, timing, retries
- Standard Tasker observability for each step

**Layer 6: Agent Lineage** (for agent-created task chains)

- `parent_correlation_id` chain visualization
- Task-level progression: research → analysis → workflow → execution
- Aggregate resource consumption across the delegation chain
- Agent decision points (implicit, inferred from task creation patterns)

### Principle 4: Bounded Blast Radius

Dynamic planning introduces new classes of failure: a planning step generates a fragment that, while valid, produces poor results. A grammar composition passes structural validation but behaves unexpectedly at runtime. An agent creates a long chain of research tasks without converging on a design.

These failures are bounded by design:

- Each planning step's fragment has resource limits (max steps, max depth)
- Task-level budgets cap total resource consumption across all phases
- Grammar compositions are validated against structural invariants before execution
- Convergence points are declared in the template (the *frame*), not by the planner
- Agent delegation chains have depth and budget limits
- The worst case is a task (or task chain) that consumes its budget without producing useful results — disappointing but not dangerous

**Implication:** Budget consumption should be a first-class metric. Operators should see: "This task has used 47 of 100 step budget, 3 of 5 planning phases, $2.30 of $5.00 cost budget." For agent delegation chains: "This chain has 3 tasks across 2 delegation levels, consuming $12.40 of $50.00 aggregate budget."

### Principle 5: The Template is the Safety Contract

Even with dynamic planning and agent integration, the task template is the safety contract between the workflow author and the system. The template declares:

- What happens before planning (static steps)
- Where planning occurs (planning steps with constraints)
- What happens after planning (convergence and finalization)
- What the resource bounds are
- Whether dynamic composition beyond common patterns is allowed

The planner fills in the middle. It cannot modify the frame. It cannot bypass convergence. It cannot exceed its bounds. The template author retains control of the workflow's structure; they delegate the topology of specific segments.

For agent-created tasks, the template still provides the safety contract. The agent selects which template to use (or constructs a task with planning steps), but the template's constraints apply regardless of who submitted the task.

**Implication:** Template review is the primary code review artifact for dynamic workflows. If the template's constraints are correct, the system's behavior is bounded regardless of what the planner or agent does.

---

## Observability Architecture for Dynamic Workflows

### Telemetry Extensions

**Standard telemetry** (emitted by all steps, unchanged):

- Step lifecycle events (created, enqueued, claimed, executing, completed/failed)
- Step execution metrics (latency, retry count, handler name)
- Task lifecycle events (created, in_progress, completed/failed)
- Queue metrics (depth, claim rate, processing time)

**Planning telemetry** (emitted by planning steps, in addition to standard):

- LLM call metrics (model, token count input/output, latency, cost)
- Fragment generation metrics (steps planned, depth, handler distribution by type)
- Validation metrics (pass/fail, rejection reasons, retry count)
- Budget consumption (steps used / remaining, phases used / remaining, cost used / remaining)

**Composition telemetry** (emitted by grammar-composed steps, in addition to standard):

- Composition specification (primitives, configuration)
- Whether the composition referenced a common pattern or was dynamically assembled
- Structural invariant validation result (pass, with any warnings)
- Per-primitive timing (if captured — useful for identifying bottleneck primitives)

**Provenance telemetry** (emitted when dynamic steps are created):

- Step creation source (planning_step_uuid, fragment_id)
- Step's position in fragment DAG (depth, breadth)
- Planning phase identifier
- Handler type (grammar, application)

**Agent lineage telemetry** (emitted for tasks with parent_correlation_id):

- Delegation depth (how many levels deep in the chain)
- Aggregate step count and cost across the chain
- Task creation timing (latency between parent task completion and child task creation)

### Correlation Strategy

All telemetry for a dynamic workflow is correlated through existing mechanisms:

- **Task UUID**: Groups all steps (planned and static) in a single workflow
- **Trace ID**: Spans the entire task lifecycle, including planning
- **Planning Step UUID**: Links planned steps to their planner (via provenance metadata)
- **Fragment ID**: Groups steps from a single planning decision
- **parent_correlation_id**: Links tasks in an agent delegation chain

No new correlation mechanism is needed. The existing task → step hierarchy, extended with provenance metadata and the existing `parent_correlation_id`, supports all drill-down patterns.

### Dashboarding Patterns

**Task-Level Dashboard** (extends existing):

- Task completion rate, segmented by planning phase count
- Average steps per task (static vs. dynamic, grammar vs. application)
- Budget utilization distribution (histogram)
- Planning success rate (fragments generated vs. fragments validated)

**Planning-Specific Dashboard** (new):

- LLM call volume and latency
- Most frequently used common patterns in planned fragments
- Most frequently dynamically composed handler patterns
- Fragment validation failure rate by rejection reason
- Cost per planning phase, averaged across tasks
- Planning depth distribution (how many phases do tasks actually use?)

**Grammar Composition Dashboard** (new):

- Handler usage distribution (common patterns vs. dynamic compositions)
- Handler execution success rate by handler type (grammar vs. application)
- Performance by handler (latency distribution per common pattern)
- Dynamic composition pattern frequency (candidates for named common patterns)
- Configuration pattern analysis (what configurations are most common?)

**Agent Activity Dashboard** (new):

- Tasks created by agents (volume, success rate)
- Delegation chain depth distribution
- Agent-to-decision latency (how long from first research task to final workflow)
- Aggregate resource consumption by agent delegation chain
- Research task convergence quality (how useful are research results to subsequent decisions?)

### Alerting Patterns

| Alert | Trigger | Action |
|-------|---------|--------|
| Planning step timeout | LLM call exceeds configured timeout | Retry or fail step based on retry policy |
| Fragment validation failure rate | > 30% of planning steps produce invalid fragments | Review capability schema, planning prompts |
| Dynamic composition runtime failure spike | Dynamically composed handlers failing at higher rate than common patterns | Review structural validation coverage, common failure compositions |
| Budget consumption anomaly | Task consuming budget > 2σ from mean | Investigate planning decisions, consider tighter bounds |
| Common pattern error spike | Handler failure rate > threshold | Investigate handler configuration patterns |
| Planning depth anomaly | Tasks consistently reaching max phases without converging | Review problem descriptions, planning prompts, or increase bounds |
| Agent delegation depth anomaly | Agent chains consistently reaching max depth | Review agent decomposition patterns, consider wider investigation templates |

---

## LLM Context Management

### The Context Window as a Design Constraint

The LLM planner's effectiveness is directly proportional to the quality of information in its context window. Too little information and the planner makes poor decisions. Too much and the planner loses focus or hits token limits. This is a design constraint, not a runtime problem — the system must be designed to provide the right information in the right format.

### Context Composition

The planning prompt is composed from these sources, in priority order:

1. **Problem description** (from task context): What needs to be accomplished. Always included in full.
2. **Accumulated results** (from prior phases): What has been learned. Summarized if large.
3. **Capability schema** (from grammar primitives and common patterns): What the planner can use, including common patterns and composition rules. Potentially large; strategy required.
4. **Planning constraints** (from template): Resource bounds, required convergence. Always included.
5. **Failure context** (if retrying): What went wrong. Included on retry.
6. **Examples** (from prompt engineering): Few-shot demonstrations. Carefully curated.

### Capability Schema Compression

The full capability schema for all common patterns plus the grammar's composition rules may exceed practical context window budgets. Strategies:

**Tiered description:**

- Tier 1: Handler name + one-line description, primitive name + one-line description (always included)
- Tier 2: Input/output schemas (included for handlers the planner selects)
- Tier 3: Full configuration reference (included on request or for complex handlers)
- Composition rules (including single-mutation boundary): always included at Tier 1 (the rules are compact); specific primitive schemas at Tier 2

**Category-based inclusion:**

- Include full schemas only for primitive categories relevant to the problem type
- Data processing problems get full `transform`, `validate`, `fan_out` schemas
- API integration problems get full `http_request`, `auth` schemas
- Control flow gets `decide`, `gate` schemas

**Empirical calibration:**

- Measure planning quality as a function of schema detail
- Find the minimum schema detail that produces valid fragments > 90% of the time
- This will vary by LLM model; calibrate per supported model

### Result Summarization

Between planning phases, accumulated results must be compressed. The summarization strategy depends on result size:

| Result Size | Strategy | Example |
|-------------|----------|---------|
| < 1KB | Include verbatim | Status codes, counts, small payloads |
| 1KB - 10KB | Structured summary | Key fields extracted, schema preserved |
| 10KB - 100KB | LLM-generated summary | Dedicated summarization step before next planning step |
| > 100KB | Reference with metadata | Object store reference + schema + size + sample |

The summarization strategy should be configurable per planning step, with sensible defaults.

---

## Operator Experience Design

### Mental Model

The operator's mental model for dynamic workflows should be:

> "This workflow has a frame (the template) and fill (the planned steps). The frame is static and reviewed like any template. The fill is dynamic and generated by a planner. Fill steps use grammar compositions — some reference common patterns, others are composed dynamically from primitives. I monitor everything through the same tools, with drill-down into planning decisions and composition details when I need it."

For agent-created workflows:

> "An agent created a chain of tasks — first research, then execution. Each task is a normal Tasker task. I can see the chain through the parent_correlation_id lineage. Each task has its own frame and fill."

These are the *only* new concepts operators need to learn. Everything else — step states, retries, convergence, DLQ — works the same way.

### Investigation Workflow

When a dynamic workflow fails, the operator's investigation follows this path:

1. **What failed?** → Standard step failure view. Same as static workflows.
2. **Was this step planned or static?** → Provenance metadata. One field check.
3. **If planned: what kind of handler?** → `handler_type` metadata. Grammar or application.
4. **If grammar: what was the composition?** → `composition_spec` metadata. See which primitives were used and whether it referenced a common pattern or was dynamically composed.
5. **What was the planning decision?** → Drill into planning step. See fragment, reasoning, validation.
6. **Was the plan reasonable?** → Evaluate fragment structure, handler selection, configuration.
7. **If plan was bad: why?** → Examine planning prompt, context, LLM response. Identify whether the issue is schema quality, context quality, or model quality.
8. **If plan was good but execution failed: why?** → Standard step debugging. Inputs, outputs, error messages, retry history.
9. **Is this part of an agent chain?** → Check `parent_correlation_id`. Trace lineage to understand the broader investigation arc.

Steps 1-4 add approximately 15 seconds to investigation time. Steps 5-7 are new but only needed when the failure is planning-related. Steps 8-9 are unchanged or trivial lookups.

### Runbooks

Dynamic workflows should ship with runbook extensions that cover:

- "A planning step is in DLQ" — how to investigate and resolve
- "A grammar-composed step failed" — how to examine the composition and identify the failing primitive
- "A task is consuming its budget without completing" — how to diagnose and intervene
- "Fragment validation failures are spiking" — how to diagnose capability schema issues
- "An LLM provider is returning errors" — how to fail over or degrade gracefully
- "An agent delegation chain is growing without converging" — how to investigate and intervene

---

## Avoiding Complication: Anti-Patterns

These are specific patterns that introduce complication without corresponding complexity. The system design should prevent them.

| Anti-Pattern | Why It's Complication | Prevention |
|---|---|---|
| Different observability for dynamic vs. static steps | Operators must maintain two mental models | All steps emit identical telemetry; provenance is metadata |
| Different observability for common patterns vs. dynamic compositions | Operators must learn new debugging tools | All grammar compositions emit identical step telemetry; composition source is drill-down metadata |
| Planning logic embedded in handler configuration | Handler behavior becomes unpredictable | Handlers are deterministic; planning is a separate step type |
| Fragment schema coupled to Tasker internals | LLM must understand orchestration mechanics | Fragment schema expresses intent; materialization is the system's job |
| Budget controls scattered across configuration | No single place to understand resource limits | Budget hierarchy in task template, visible and auditable |
| Context accumulation that silently drops information | Planning quality degrades mysteriously | Explicit summarization steps with configurable strategies |
| Capability schema that describes implementation | LLM reasons about wrong abstractions | Capability schema describes *what*, never *how*. Derived from grammar types, not hand-authored |
| Action grammar internals exposed to operators | Operators must understand Rust trait composition | Grammar compositions are opaque to the operator; they see "http_request handler" not "Acquire → Transform → Validate" |
| Runtime validation duplicating compile-time checks | Wasted cycles and confusing error messages | Primitive correctness is verified at compile time; composition correctness at assembly time; runtime validates only fragment references |
| Agent-specific task types or APIs | Agents appear as a special class of client | All tasks are identical; agents use the same API as any client |
| Agent delegation tracking in a separate system | Lineage requires cross-system correlation | `parent_correlation_id` is a standard task field; lineage queries use standard task queries |
| Grammar composition details exposed in workflow visualization by default | Operators see implementation details they don't need | Composition details are available on drill-down, not in the default step view |

---

## Summary: The Complexity Budget

Every system has a complexity budget — the amount of complexity humans can manage before the system becomes opaque. Dynamic workflow planning spends from this budget. The question is whether we get proportional value.

**What we spend:**

- One new step type (planning step)
- One new concept (workflow fragments)
- One new compositional layer (action grammar primitives — but invisible to operators)
- One new metadata layer (planning and composition provenance)
- One new resource dimension (planning budgets)
- One new trust distinction (developer-authored handlers vs. system-invoked grammar compositions)
- One new client pattern (agents as task-creating clients — but using existing APIs)

**What we get:**

- Workflows that adapt to their inputs
- Multi-phase problem solving with accumulated context
- Composition of generic capabilities without custom code, with compile-time verified primitives and assembly-time validated compositions
- Dynamic compositions that can be constructed for any problem without registering new patterns
- Agents that can structure their own investigation using Tasker's execution guarantees
- Gradual automation of workflow design — from developer tooling (Phase 0) through agent-driven workflows
- A type system for workflow actions that makes the vocabulary extensible without sacrificing safety

**What we protect:**

- The step as the atomic unit (unchanged)
- Execution guarantees (unchanged)
- Observability patterns (extended, not replaced)
- Operator investigation workflows (extended, not replaced)
- Template as safety contract (strengthened, not weakened)
- API uniformity (agents use the same APIs as any client)

**What we actively reduce:**

- Runtime type errors in handler compositions (primitives verified at compile time, compositions validated at assembly time)
- Capability schema drift from implementation (schemas derived from types, not hand-maintained)
- Configuration-driven failure modes (grammar compositions are verified before they can be referenced)
- Agent investigation overhead (structured research workflows replace ad hoc manual investigation)

The complexity budget is balanced when the new capabilities justify the new concepts, and the existing foundations are preserved. This document's purpose is to ensure we stay within budget.

---

*This document applies to all phases of the generative workflow initiative and the agent integration patterns. It should be reviewed and updated as each phase is implemented and operational experience reveals new complexity management needs.*
