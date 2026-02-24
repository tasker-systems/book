# Phase 3: Recursive Planning and Adaptive Workflows

*Multi-phase workflows where each phase's plan is informed by previous results — at both step level and task level*

---

## Phase Summary

Recursive planning enables workflows where the path forward is not just unknown at task creation time — it is *unknowable* until intermediate results are observed. A planning step generates a workflow fragment, that fragment executes, and a subsequent planning step uses the accumulated results to plan the next phase. This is not iteration in a loop; it is phased problem-solving where each phase operates with strictly more information than the one before.

This capability operates at two distinct levels:

**Step-level recursion** occurs within a single task. Planning steps generate workflow fragments, those fragments execute, and subsequent planning steps within the same task plan the next phase based on accumulated results. The task template defines the frame (what happens before and after planning); the planners fill in the middle. All steps share a single task lifecycle, budget, and convergence structure.

**Task-level delegation** occurs across tasks. An external client — typically an agent (see [Agent Orchestration](05-agent-orchestration.md)) — creates a task, receives its results, reasons about them externally, and creates follow-up tasks based on that reasoning. The `parent_correlation_id` field traces the chain across tasks. Each task has its own lifecycle and budget, but the reasoning chain is observable as a unit.

These two levels are complementary, not competing. Step-level recursion handles multi-phase *execution* within a bounded problem. Task-level delegation handles multi-phase *investigation and decision-making* where the reasoning between phases is too complex or context-dependent for an in-workflow planning step. An agent might create a research task (task-level delegation), and that research task might contain planning steps that adapt to intermediate findings (step-level recursion). The levels compose naturally.

This is the full realization of the vision: a system that can approach a problem the way a thoughtful engineer would — reconnaissance first, then analysis, then execution, then validation — with each phase adapting to what was learned. Whether the adaptation happens within a task (step-level) or across tasks (task-level), the execution guarantees are identical.

---

## Research Areas

### 1. Context Accumulation and Propagation

**Question:** How do results from earlier phases flow into subsequent planning steps?

**Research approach:**

- Study current `dependency_results` propagation patterns in conditional and batch workflows
- Design a context accumulation strategy that provides sufficient information for planning without overwhelming the LLM's context window
- Leverage typed data contracts from action grammars to improve summarization accuracy
- Distinguish context flow patterns for step-level (within-task) and task-level (cross-task) recursion

**The context problem:**

In a two-phase workflow — plan → execute → plan → execute — the second planning step needs to know:

1. What the original problem was (task context)
2. What the first planning step decided and why (planning metadata)
3. What the first phase's execution produced (step results)
4. What went wrong, if anything (failure information from retried or failed steps)

For a three-phase workflow, the third planner needs all of the above for both prior phases. Context accumulates linearly with phases. With large step results (API responses, processed datasets), the accumulated context can exceed LLM context windows.

**Step-level vs. task-level context flow:**

For step-level recursion, context flows through Tasker's standard `dependency_results` mechanism — each planning step has access to its declared upstream steps' results. The context is internal to the task and fully managed by the orchestration layer.

For task-level delegation, context flows through the agent. The agent receives task results through the API, processes or summarizes them in its own reasoning, and provides relevant context as input when creating the next task. Tasker does not manage cross-task context propagation — the agent is responsible for deciding what context the next task needs.

This separation is intentional. Step-level context is bounded by the task's scope and managed by the system. Task-level context is unbounded in principle but managed by the agent, which can apply its own judgment about what's relevant. The agent's ability to filter, prioritize, and restructure context between tasks is a feature, not a limitation.

**The typed data contract advantage:**

Because grammar-backed steps have declared output contracts (from Phase 1), the context accumulation layer knows the *shape* of each step's result without inspecting the data. This enables more intelligent summarization — the system can summarize a step's results according to its output contract's type structure, preserving key fields and eliding bulk data, rather than attempting generic JSON summarization. This applies to both step-level accumulation (system-managed) and task-level accumulation (agent-managed, but aided by schema metadata).

**Proposed context accumulation patterns:**

| Pattern | Level | Description | When to Use |
|---------|-------|-------------|-------------|
| **Full propagation** | Step | All prior results passed to planner | Small results, shallow recursion (2-3 phases) |
| **Contract-guided summarization** | Step | Results summarized according to their output contract types, preserving structure | Medium results, typed step outputs |
| **LLM-generated summary** | Step | Dedicated summarization step before next planning step | Large results, deep recursion |
| **Selective propagation** | Step | Planner declares which upstream results it needs; only those are passed | When the planner can predict its own information needs |
| **Hierarchical propagation** | Step | Each planning step receives only its immediate predecessor's summary | Deep recursion with clear phase boundaries |
| **Agent-mediated propagation** | Task | Agent receives full results, applies its own reasoning and filtering, provides curated context to next task | Cross-task reasoning where judgment about relevance is needed |

**Open questions:**

- Should context accumulation be explicit (planner declares what it needs) or implicit (system provides everything available)?
- How should we handle the case where a planner needs raw data from two phases ago, not just the summary?
- Should accumulated context be stored as a separate artifact from step results? (e.g., a `planning_context` field on the task that grows across phases)
- What is the practical depth limit before context quality degrades? (Likely 3-5 phases based on LLM context window constraints)
- For task-level delegation, should Tasker provide schema metadata in task results to help agents understand result structure?

### 2. Planning Depth and Breadth Controls

**Question:** How do we prevent recursive planning from generating arbitrarily large or deep workflows?

**Research approach:**

- Define resource consumption model for recursive planning (LLM calls, steps created, wall-clock time, external API calls)
- Design hierarchical budgets that constrain planning at each level
- Study termination guarantees in recursive systems
- Define resource controls for task-level delegation (per-task budgets, not cross-task budgets)

**Budget hierarchy (step-level recursion):**

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

**Resource controls for task-level delegation:**

For task-level delegation, each task has its own independent budget. Tasker does not enforce cross-task budget hierarchies — an agent creating three investigation tasks gets three independent task budgets. The agent is responsible for its own delegation budgets:

- Deciding how many investigation tasks to create
- Setting appropriate resource bounds on each task
- Managing total resource consumption across its reasoning chain

Tasker provides the *per-task* controls; the agent provides the *chain-level* controls. This is consistent with the agent-as-client model: Tasker provides infrastructure, not agency.

That said, the `parent_correlation_id` enables *observability* across the chain. An operator can query total resource consumption for all tasks sharing a correlation ID, even though Tasker doesn't enforce it. This allows after-the-fact analysis of agent resource usage without requiring real-time cross-task budget management.

**Termination guarantees (step-level):**

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
- Should Tasker provide an optional cross-task budget mechanism for agent chains, or is per-task sufficient?

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
- Distinguish patterns that work best as step-level recursion from those that benefit from task-level delegation

**Proposed canonical patterns:**

**Pattern 1: Reconnaissance → Execution (Step-Level)**

```
ingest → plan_recon → [recon steps] → plan_execution → [execution steps] → finalize
```

The reconnaissance phase gathers information (API calls, data profiling, schema inspection). The execution phase acts on what was learned. Two planning steps within a single task, each informed by the prior phase's results. Typed data contracts from the recon phase's grammar-composed steps ensure the execution planner receives well-structured context.

*Best for:* Problems where the reconnaissance is bounded and the context can flow through the task's step-level accumulation.

**Pattern 2: Iterative Refinement (Step-Level)**

```
ingest → plan_v1 → [execute] → evaluate → plan_v2 → [execute] → evaluate → converge
```

Each phase attempts a solution. An evaluation step (which could be LLM-backed) assesses the results. If the results are insufficient, another planning phase refines the approach. Budget controls limit iterations.

*Best for:* Optimization problems where each iteration is structurally similar and the evaluation criteria are known upfront.

**Pattern 3: Map → Analyze → Reduce (Step-Level)**

```
ingest → plan_map → [fan_out batch processing] → plan_analyze → [analysis steps] → reduce
```

The map phase parallelizes work across a dataset using the FanOut grammar primitive. The analysis phase examines aggregated results. The reduce phase produces final output. Planning enables each phase to adapt to the data's characteristics.

*Best for:* Data processing pipelines where the shape of analysis depends on the data.

**Pattern 4: Progressive Disclosure (Step-Level)**

```
ingest → plan_triage → [triage steps] → route_by_complexity →
  simple: plan_simple → [quick steps] → converge
  complex: plan_deep → [thorough steps] → converge
```

Initial triage determines problem complexity. Simple problems get lightweight plans. Complex problems get thorough plans. The planning steps at each level are scoped to the problem's complexity.

*Best for:* Heterogeneous problem sets where different inputs require different treatment.

**Pattern 5: Investigation → Design → Execute (Task-Level)**

```
Agent creates research_task → [investigation steps, possibly with step-level planning]
Agent receives research results, reasons about them
Agent creates design_task → [workflow design, possibly with planning steps]
Agent receives design, reviews or adjusts
Agent creates execution_task → [the actual workflow]
```

The agent uses task-level delegation for the high-level phases (investigate, design, execute) because its reasoning between phases requires context that cannot be captured in a planning step's prompt. Within each task, step-level planning may be used for tactical adaptation.

*Best for:* Problems where the reasoning between phases is complex, context-dependent, or requires external judgment.

**Pattern 6: Parallel Investigation with Synthesis (Task-Level)**

```
Agent creates investigation_task_A (source 1)
Agent creates investigation_task_B (source 2)
Agent creates investigation_task_C (source 3)
Agent waits for all three, synthesizes findings
Agent creates design_or_action_task based on synthesis
```

The agent fans out investigation across multiple independent research tasks, synthesizes the results externally, and acts on the synthesis. This is similar to Pattern 1 but with the fan-out happening at the task level rather than the step level — useful when the investigation dimensions are truly independent and the synthesis requires agent-level reasoning.

*Best for:* Complex decisions requiring information from multiple independent domains.

**Open questions:**

- Are there patterns that require capabilities beyond what Phases 0-2 provide?
- Should pattern selection itself be LLM-assisted? (Meta-planning: "given this problem, which multi-phase pattern is most appropriate?")
- How do we document and catalog these patterns for users?
- Should there be a library of research workflow templates in `tasker-contrib` for the task-level patterns?

### 5. Failure Recovery in Multi-Phase Workflows

**Question:** How does the system recover when a phase fails in the middle of a multi-phase workflow?

**Research approach:**

- Map existing retry/backoff semantics to multi-phase contexts
- Design recovery strategies for planning step failures vs. execution step failures
- Evaluate checkpoint and resume semantics across planning phases
- Distinguish recovery for step-level failures (system-managed) from task-level failures (agent-managed)

**Failure categories (step-level):**

| Failure | Scope | Recovery Strategy |
|---------|-------|-------------------|
| Planning step LLM call fails | Single step | Standard retry with backoff. LLM calls are idempotent (stateless). |
| Planning step generates invalid fragment | Single step | Retry with validation feedback to LLM. Limited attempts before permanent failure. |
| Execution step in planned fragment fails | Single step | Standard step retry semantics. Same as any Tasker step. |
| Entire planned phase fails (all steps) | Phase | Phase-level retry: re-plan from the last successful phase boundary. |
| Budget exhausted mid-phase | Phase | Graceful degradation: force convergence with partial results + diagnostic. |
| Recursive planning exceeds depth | Task | Hard stop. Planning step fails with "depth exceeded" error. Task may converge with partial results or fail entirely depending on template design. |

**Failure categories (task-level):**

| Failure | Scope | Recovery Strategy |
|---------|-------|-------------------|
| Investigation task fails | Single task | Agent receives failure notification. Agent decides whether to retry (create new task) or proceed without that investigation. |
| Agent-side failure between tasks | Agent | Not Tasker-observable. The task chain simply stops. `parent_correlation_id` shows the last completed task. |
| Multiple investigation tasks fail | Chain | Agent manages multi-failure scenarios. May create a fallback investigation task, proceed with partial information, or escalate to human review. |

The key distinction: step-level failure recovery is *system-managed* — Tasker's orchestration layer handles retries, budget checks, and convergence. Task-level failure recovery is *agent-managed* — the agent decides how to respond to failed tasks. This matches the agent-as-client model: Tasker guarantees individual task execution; the agent guarantees reasoning chain coherence.

**Phase-level retry** is the novel step-level pattern. If an entire planned phase fails, the system could re-invoke the planning step with the accumulated context plus failure information. The planner can then generate a revised fragment that accounts for what failed. This requires:

- Clear phase boundaries (which the planning step + convergence pattern provides)
- Failure context propagation to the planner
- Budget accounting that doesn't penalize retried phases excessively

**Open questions:**

- Should phase-level retry be automatic or require human approval (gate step)?
- How many phase-level retries are reasonable? (Likely 1-2 before requiring human intervention)
- Should the revised plan have access to the failed plan for comparison? (Useful for "don't try the same thing again")
- For task-level delegation, should Tasker provide a callback/webhook mechanism so agents learn about task completion without polling?

---

## Prototyping Goals

### Prototype 1: Two-Phase Adaptive Workflow (Step-Level)

**Objective:** Implement the Reconnaissance → Execution pattern with two planning steps within a single task.

**Success criteria:**

- First planning step gathers information and produces results
- Second planning step receives first phase's results (with typed context from grammar-backed steps) and plans execution
- Execution phase completes using grammar-composed handlers
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

### Prototype 4: Agent-Driven Investigation Chain (Task-Level)

**Objective:** Demonstrate an agent creating a research task, receiving results, and creating a follow-up task based on findings.

**Success criteria:**

- Agent creates an investigation task with appropriate resource bounds
- Investigation task executes with fan-out, convergence, and structured results
- Agent receives results through the API
- Agent creates a follow-up task with curated context from investigation results
- `parent_correlation_id` traces the entire chain
- Total resource consumption across the chain is observable

---

## Validation Criteria for Phase Completion

1. Multi-phase workflow with at least 2 planning steps executes end-to-end (step-level)
2. Context accumulation provides sufficient information for subsequent planning steps, with typed data contracts improving summarization accuracy
3. Budget hierarchy enforced: task-level, phase-level, and per-fragment limits
4. Recursive planning terminates under all conditions (depth limits, budget exhaustion)
5. At least 2 step-level canonical patterns (of the 4 proposed) demonstrated with real use cases
6. At least 1 task-level delegation pattern demonstrated end-to-end
7. Phase-level failure recovery demonstrated (re-planning after phase failure)
8. Convergence works correctly with dynamically determined upstream steps
9. Full observability across all planning phases and across agent task chains (see Complexity Management document)

---

## Relationship to Other Phases

- **Phase 0** provides data contract patterns that inform context accumulation design.
- **Phase 1** is foundational: grammar-composed handlers execute at every phase, and typed output contracts improve cross-phase context quality.
- **Phase 2** is a direct prerequisite: recursive planning is nested planning steps.
- **Agent orchestration** composes with this phase: task-level delegation provides the cross-task investigation pattern that complements within-task step-level recursion.

---

*This is the most speculative phase of the initiative. Many design questions will be informed by operational experience with Phase 2. This document should be substantially revised after Phase 2 validation.*
