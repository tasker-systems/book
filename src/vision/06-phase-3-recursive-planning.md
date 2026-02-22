# Phase 3: Recursive Planning and Adaptive Workflows

*Multi-phase workflows where each phase's plan is informed by previous results*

---

## Phase Summary

Recursive planning enables workflows where the path forward is not just unknown at task creation time — it is *unknowable* until intermediate results are observed. A planning step generates a workflow fragment, that fragment executes, and a subsequent planning step uses the accumulated results to plan the next phase. This is not iteration in a loop; it is phased problem-solving where each phase operates with strictly more information than the one before.

This is the full realization of the vision: a system that can approach a problem the way a thoughtful engineer would — reconnaissance first, then analysis, then execution, then validation — with each phase adapting to what was learned. The action grammar's typed data contracts make context accumulation more reliable — schemas are known, not guessed — and the grammar's compositional vocabulary grows richer with each phase of planning experience.

---

## Research Areas

### 1. Context Accumulation and Propagation

**Question:** How do results from earlier phases flow into subsequent planning steps?

**Research approach:**

- Study current `dependency_results` propagation patterns in conditional and batch workflows
- Design a context accumulation strategy that provides sufficient information for planning without overwhelming the LLM's context window
- Leverage typed data contracts from action grammars to improve summarization accuracy

**The context problem:**

In a two-phase workflow — plan → execute → plan → execute — the second planning step needs to know:

1. What the original problem was (task context)
2. What the first planning step decided and why (planning metadata)
3. What the first phase's execution produced (step results)
4. What went wrong, if anything (failure information from retried or failed steps)

For a three-phase workflow, the third planner needs all of the above for both prior phases. Context accumulates linearly with phases. With large step results (API responses, processed datasets), the accumulated context can exceed LLM context windows.

**The typed data contract advantage:**

Because grammar-backed steps have declared output contracts (from Phase 1), the context accumulation layer knows the *shape* of each step's result without inspecting the data. This enables more intelligent summarization — the system can summarize a step's results according to its output contract's type structure, preserving key fields and eliding bulk data, rather than attempting generic JSON summarization.

**Proposed context accumulation patterns:**

| Pattern | Description | When to Use |
|---------|-------------|-------------|
| **Full propagation** | All prior results passed to planner | Small results, shallow recursion (2-3 phases) |
| **Contract-guided summarization** | Results summarized according to their output contract types, preserving structure | Medium results, typed step outputs |
| **LLM-generated summary** | Dedicated summarization step before next planning step | Large results, deep recursion |
| **Selective propagation** | Planner declares which upstream results it needs; only those are passed | When the planner can predict its own information needs |
| **Hierarchical propagation** | Each planning step receives only its immediate predecessor's summary | Deep recursion with clear phase boundaries |

**Open questions:**

- Should context accumulation be explicit (planner declares what it needs) or implicit (system provides everything available)?
- How should we handle the case where a planner needs raw data from two phases ago, not just the summary?
- Should accumulated context be stored as a separate artifact from step results? (e.g., a `planning_context` field on the task that grows across phases)
- What is the practical depth limit before context quality degrades? (Likely 3-5 phases based on LLM context window constraints)

### 2. Planning Depth and Breadth Controls

**Question:** How do we prevent recursive planning from generating arbitrarily large or deep workflows?

**Research approach:**

- Define resource consumption model for recursive planning (LLM calls, steps created, wall-clock time, external API calls)
- Design hierarchical budgets that constrain planning at each level
- Study termination guarantees in recursive systems

**Budget hierarchy:**

```
Task-level budget (set by template author or operator):
  ├── max_total_planning_phases: 5
  ├── max_total_steps: 100
  ├── max_total_llm_calls: 10
  ├── max_wall_clock_time: 30m
  └── max_cost_budget: $5.00
      │
      ├── Phase 1 planning step budget (subset of task budget):
      │   ├── max_fragment_steps: 20
      │   ├── max_fragment_depth: 3
      │   └── remaining_budget: inherited from task level, minus consumed
      │
      └── Phase 2 planning step budget (further subset):
          ├── max_fragment_steps: min(20, remaining)
          ├── max_fragment_depth: 3
          └── remaining_budget: further reduced
```

**Termination guarantees:**

- Each planning step's fragment is bounded (`max_fragment_steps`, `max_fragment_depth`)
- Task-level bounds cap total growth across all phases
- Budget decrements are tracked in the task's metadata (JSONB)
- A planning step that exceeds its budget fails with a diagnostic error
- A planning step that requests resources exceeding the remaining budget is rejected at validation

**The "infinite planner" problem:** A planning step could, in theory, always create another planning step as part of its fragment — infinite recursion. Prevention:

- `max_total_planning_phases` caps the number of planning steps in a task's lifetime
- Each planning step's `max_fragment_depth` limits nesting
- Budget exhaustion provides a natural termination condition

**Open questions:**

- Should budgets be expressed in abstract units or concrete metrics? (Abstract: "complexity points"; Concrete: "LLM tokens + step count + wall time")
- How should the system behave when a budget is nearly exhausted? (Inform the planner of remaining budget so it can plan conservatively?)
- Should there be an "emergency convergence" mechanism that forces a workflow to converge when budgets are low?
- How do we account for retry costs? (A step that fails and retries 3 times consumes budget for each attempt)

### 3. Adaptive Convergence

**Question:** How should convergence work when the topology is determined across multiple planning phases?

**Research approach:**

- Extend current deferred/intersection convergence semantics to multi-phase contexts
- Design patterns for convergence steps that may not know all upstream steps at creation time
- Evaluate whether new convergence semantics are needed or existing mechanisms suffice

**Challenge:** In a single-phase conditional workflow, the convergence step declares all possible dependencies and uses intersection semantics. In a multi-phase workflow, the convergence step at the task template level doesn't know what steps will exist in the middle — those are planned dynamically.

**Proposed approach: Convergence declarations on planning steps.**

The task template declares that a planning step's output should converge to a specific convergence step. The planning step includes convergence information in its fragment. The orchestration layer ensures that all terminal steps in the fragment connect to the declared convergence point.

```yaml
# In the task template:
steps:
  - name: plan_phase_1
    type: planning
    dependencies: [ingest]
    convergence_target: finalize  # Fragment must converge here

  - name: finalize
    type: deferred
    dependencies: [plan_phase_1]
    handler:
      callable: FinalizationHandler
```

The planning step's fragment must declare a convergence point. The orchestration layer validates that the fragment's terminal steps connect to the declared `convergence_target`. If the fragment includes a nested planning step, that step's convergence target is the outer convergence — recursive convergence resolution.

**Open questions:**

- Can a planning step declare its *own* convergence step, or must convergence always be declared in the task template?
- How should convergence interact with partial failure? (If 3 of 5 planned steps complete but 2 fail permanently, does convergence fire with partial results?)
- Should the convergence step know how many upstream steps were planned? (Useful for aggregation, but creates coupling between planner and convergence handler)

### 4. Multi-Phase Workflow Patterns

**Question:** What are the common patterns for multi-phase adaptive workflows?

**Research approach:**

- Identify canonical problem types that benefit from multi-phase planning
- Design reference architectures for each pattern
- Validate with concrete use cases

**Proposed canonical patterns:**

**Pattern 1: Reconnaissance → Execution**

```
ingest → plan_recon → [recon steps] → plan_execution → [execution steps] → finalize
```

The reconnaissance phase gathers information (API calls, data profiling, schema inspection). The execution phase acts on what was learned. Two planning steps, each informed by the prior phase's results. Typed data contracts from the recon phase's grammar-backed steps ensure the execution planner receives well-structured context.

**Pattern 2: Iterative Refinement**

```
ingest → plan_v1 → [execute] → evaluate → plan_v2 → [execute] → evaluate → converge
```

Each phase attempts a solution. An evaluation step (which could be LLM-backed) assesses the results. If the results are insufficient, another planning phase refines the approach. Budget controls limit iterations.

**Pattern 3: Map → Analyze → Reduce**

```
ingest → plan_map → [fan_out batch processing] → plan_analyze → [analysis steps] → reduce
```

The map phase parallelizes work across a dataset using the FanOut grammar primitive. The analysis phase examines aggregated results. The reduce phase produces final output. Planning enables each phase to adapt to the data's characteristics.

**Pattern 4: Progressive Disclosure**

```
ingest → plan_triage → [triage steps] → route_by_complexity →
  simple: plan_simple → [quick steps] → converge
  complex: plan_deep → [thorough steps] → converge
```

Initial triage determines problem complexity. Simple problems get lightweight plans. Complex problems get thorough plans. The planning steps at each level are scoped to the problem's complexity.

**Open questions:**

- Are there patterns that require capabilities beyond what Phases 0-2 provide?
- Should pattern selection itself be LLM-assisted? (Meta-planning: "given this problem, which multi-phase pattern is most appropriate?")
- How do we document and catalog these patterns for users?

### 5. Failure Recovery in Multi-Phase Workflows

**Question:** How does the system recover when a phase fails in the middle of a multi-phase workflow?

**Research approach:**

- Map existing retry/backoff semantics to multi-phase contexts
- Design recovery strategies for planning step failures vs. execution step failures
- Evaluate checkpoint and resume semantics across planning phases

**Failure categories:**

| Failure | Scope | Recovery Strategy |
|---------|-------|-------------------|
| Planning step LLM call fails | Single step | Standard retry with backoff. LLM calls are idempotent (stateless). |
| Planning step generates invalid fragment | Single step | Retry with validation feedback to LLM. Limited attempts before permanent failure. |
| Execution step in planned fragment fails | Single step | Standard step retry semantics. Same as any Tasker step. |
| Entire planned phase fails (all steps) | Phase | Phase-level retry: re-plan from the last successful phase boundary. |
| Budget exhausted mid-phase | Phase | Graceful degradation: force convergence with partial results + diagnostic. |
| Recursive planning exceeds depth | Task | Hard stop. Planning step fails with "depth exceeded" error. Task may converge with partial results or fail entirely depending on template design. |

**Phase-level retry** is the novel pattern here. If an entire planned phase fails, the system could re-invoke the planning step with the accumulated context plus failure information. The planner can then generate a revised fragment that accounts for what failed. This requires:

- Clear phase boundaries (which the planning step + convergence pattern provides)
- Failure context propagation to the planner
- Budget accounting that doesn't penalize retried phases excessively

**Open questions:**

- Should phase-level retry be automatic or require human approval (gate step)?
- How many phase-level retries are reasonable? (Likely 1-2 before requiring human intervention)
- Should the revised plan have access to the failed plan for comparison? (Useful for "don't try the same thing again")

---

## Prototyping Goals

### Prototype 1: Two-Phase Adaptive Workflow

**Objective:** Implement the Reconnaissance → Execution pattern with two planning steps.

**Success criteria:**

- First planning step gathers information and produces results
- Second planning step receives first phase's results (with typed context from grammar-backed steps) and plans execution
- Execution phase completes using only catalog handlers
- Context accumulation works correctly across phases
- Budget tracking decrements across phases

### Prototype 2: Planning Depth Controls

**Objective:** Validate that recursive planning terminates correctly under all conditions.

**Success criteria:**

- Planning that exceeds `max_total_planning_phases` fails gracefully
- Budget exhaustion produces clean termination with diagnostic
- Partially completed phases converge with available results
- No infinite planning loops possible

### Prototype 3: Phase-Level Failure Recovery

**Objective:** Demonstrate recovery from phase failure through re-planning.

**Success criteria:**

- A planned phase with a failing step triggers re-planning
- The re-planner receives failure context and generates a revised fragment
- The revised fragment avoids the failure mode of the original
- Budget accounting is correct across retries

---

## Validation Criteria for Phase Completion

1. Multi-phase workflow with at least 2 planning steps executes end-to-end
2. Context accumulation provides sufficient information for subsequent planning steps, with typed data contracts improving summarization accuracy
3. Budget hierarchy enforced: task-level, phase-level, and per-fragment limits
4. Recursive planning terminates under all conditions (depth limits, budget exhaustion)
5. At least 2 canonical patterns (of the 4 proposed) demonstrated with real use cases
6. Phase-level failure recovery demonstrated (re-planning after phase failure)
7. Convergence works correctly with dynamically determined upstream steps
8. Full observability across all planning phases (see Complexity Management document)

---

## Relationship to Other Phases

- **Phase 0** provides data contract patterns that inform context accumulation design.
- **Phase 1** is foundational: grammar-backed catalog handlers execute at every phase, and typed output contracts improve cross-phase context quality.
- **Phase 2** is a direct prerequisite: recursive planning is nested planning steps.

---

*This is the most speculative phase of the initiative. Many design questions will be informed by operational experience with Phase 2. This document should be substantially revised after Phase 2 validation.*
