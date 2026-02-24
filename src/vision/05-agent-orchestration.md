# Agent Orchestration: Deterministic Infrastructure for Autonomous Clients

*How agents use Tasker's execution guarantees for investigation, planning, and coordinated action*

---

## Overview

Tasker is not an agent orchestration framework. Tasker is deterministic workflow infrastructure that agents use as clients.

This distinction is not semantic. An agent orchestration framework manages agent state, controls agent behavior, coordinates agent-to-agent communication, and is responsible for the correctness of agent decisions. Such a framework would require abandoning the properties that make Tasker trustworthy: determinism, predictability, transactional guarantees, and clean observability. That path is explicitly rejected.

What this document describes is the inverse: **agents as external clients that leverage Tasker's existing capabilities for their own purposes**. An agent submitting a task to Tasker is architecturally indistinguishable from a human developer or an application submitting a task. The same API. The same guarantees. The same resource controls. The same observability. Tasker does not know or care that the client is an agent — it provides infrastructure and the agent provides intent.

This capability is not a separate phase of the generative workflow initiative. It is a cross-cutting concern that composes with every phase. Phase 0's MCP server provides the agent's design-time interface. Phase 1's action grammars provide the compositional vocabulary. Phase 2's planning interface provides the runtime planning mechanism. Phase 3's recursive planning provides the multi-phase coordination pattern. Agent integration enriches and is enriched by each of these capabilities.

---

## The Context Decomposition Problem

The most powerful capability of agent systems is not reasoning — it's *delegation*. When a human expert approaches a complex problem, they don't try to hold everything in their head at once. They decompose: research this aspect, analyze that data source, compare these options, synthesize the findings, then decide. Each activity produces intermediate results that inform the next. The expert's working memory is bounded, but their problem-solving is not, because they structure their investigation to manage that bound.

LLMs face the same constraint, amplified. A context window is finite. Reasoning quality degrades as context length grows. Holding every fact needed for a complex decision simultaneously is often impossible and always suboptimal. The most effective agent architectures recognize this and delegate: spinning up sub-agents for research, parallelizing analysis across multiple sources, aggregating findings, and making decisions with the benefit of structured, converged information.

This delegation needs infrastructure. Specifically, it needs:

- **Parallel execution with convergence**: investigate multiple dimensions simultaneously, then bring the findings together
- **Transactional guarantees**: each investigation step either completes fully or fails cleanly — no half-finished research polluting the decision context
- **Bounded resource consumption**: investigation cannot run forever or consume unlimited resources
- **Observability**: every step of the investigation is traceable, timing is recorded, results are inspectable
- **Retry semantics**: transient failures in investigation (API timeouts, rate limits) are handled automatically

These are Tasker's core capabilities. They exist today, are tested, and are approaching production readiness. The agent doesn't need a new system for investigation — it needs access to the system that already provides these guarantees.

---

## The Agent-Client Pattern

### How Agents Interact with Tasker

An agent interacts with Tasker through two surfaces:

**Design time: MCP server.** The agent uses MCP tools to inspect available templates, query the action grammar vocabulary, validate proposed compositions, understand schema contracts, and generate template structures. This is the same MCP server that human developers use through their IDE — the agent simply uses it programmatically. The `tasker-tooling` crate (see [Phase 0](03-phase-0-foundation.md)) provides the shared logic that powers both the CLI and MCP interfaces, ensuring consistent behavior regardless of who the client is.

**Runtime: Tasker API.** The agent creates tasks through the standard Tasker API — the same endpoint that applications use. A task creation request includes the template reference, input data, and optionally a `parent_correlation_id` linking it to a parent task or decision context. The agent receives the task UUID and can poll for completion or subscribe to completion events.

### The `parent_correlation_id` Chain

The `parent_correlation_id` is an existing Tasker field designed for tracing second-order task dependencies. In the agent context, it becomes the thread that connects an agent's entire reasoning chain:

```
Agent receives problem description
  │
  ├── Creates research task (parent_correlation_id: agent_session_123)
  │   ├── Step: query_api_source_a (fan-out)
  │   ├── Step: query_api_source_b (fan-out)
  │   ├── Step: analyze_documentation (fan-out)
  │   └── Step: converge_findings (convergence)
  │
  ├── Receives converged research results
  │
  ├── Creates design task (parent_correlation_id: agent_session_123)
  │   ├── Step: plan_workflow (planning step, Phase 2)
  │   ├── Step: validate_design (grammar handler)
  │   └── Step: converge_design (convergence)
  │
  ├── Receives validated workflow design
  │
  └── Creates execution task (parent_correlation_id: agent_session_123)
      ├── Step: ... (the actual workflow)
      └── Step: ...
```

Every task in this chain shares the same `parent_correlation_id`. Standard Tasker telemetry — step timing, results, failures, retries — is emitted for every step. An operator can trace the entire agent reasoning chain through a single correlation ID query, seeing what the agent investigated, what it designed, and how the design executed.

### Bounded Delegation

An agent creating tasks is subject to the same resource controls as any Tasker client:

- **Task-level resource bounds:** max steps, max depth, timeout, cost budget — set per template or per task creation request
- **Rate limiting:** standard API rate limits prevent an agent from overwhelming the system
- **Template constraints:** the templates available to the agent define the shape of what it can create — an agent cannot create arbitrary topologies unless using templates designed for dynamic composition
- **Per-task isolation:** each task is independent. A failure in one agent-created task does not affect others.

The agent cannot create unbounded task chains. Each task has its own budget. The total resource consumption of an agent's reasoning chain is the sum of its individual task budgets, each of which is independently bounded.

---

## Research Workflow Patterns

The primary use case for agent-as-client is the **research workflow**: a task whose purpose is to gather, analyze, and synthesize information that the agent needs to make a decision. Research workflows are not the agent's final product — they are a preliminary phase that produces the context the agent uses for its actual work.

### Pattern 1: Parallel Investigation

The simplest research pattern fans out investigation across multiple sources and converges the findings:

```yaml
name: agent_parallel_investigation
namespace_name: agent_research
version: 1.0.0
description: "Fan-out investigation across multiple sources with convergence"

input_schema:
  type: object
  required: [investigation_queries, convergence_strategy]
  properties:
    investigation_queries:
      type: array
      items:
        type: object
        properties:
          source: { type: string }
          query: { type: string }
          expected_shape: { type: object }
    convergence_strategy:
      type: string
      enum: [merge, summarize, compare]

steps:
  - name: investigate
    type: batchable
    handler:
      grammar: http_request  # Common pattern, or dynamic composition per source
    dependencies: []
    batch:
      strategy: per_item
      source_path: "$.investigation_queries"
      max_concurrency: 10

  - name: converge_findings
    type: deferred
    handler:
      grammar: aggregate
      config:
        strategy: "${task.context.convergence_strategy}"
    dependencies:
      - investigate
```

The agent provides the investigation queries and convergence strategy. Tasker handles the parallel execution, retry semantics, and convergence. The agent receives a single converged result — a structured synthesis of all investigation threads.

### Pattern 2: Staged Investigation

When the second phase of research depends on the first phase's findings:

```yaml
name: agent_staged_investigation
namespace_name: agent_research
version: 1.0.0
description: "Multi-stage investigation where each stage informs the next"

steps:
  - name: initial_reconnaissance
    type: batchable
    handler:
      grammar: http_request
    dependencies: []
    batch:
      strategy: per_item
      source_path: "$.recon_queries"

  - name: analyze_recon
    type: standard
    handler:
      callable: agent_research.analyze_findings
    dependencies:
      - initial_reconnaissance

  - name: deep_investigation
    type: decision_point
    handler:
      callable: agent_research.plan_deep_dive
    dependencies:
      - analyze_recon
    # Decision handler examines recon results and creates
    # targeted follow-up investigation steps

  - name: synthesize
    type: deferred
    handler:
      grammar: aggregate
      config:
        strategy: summarize
    dependencies:
      - deep_investigation
```

This pattern uses Tasker's existing decision point mechanism — the `plan_deep_dive` handler examines reconnaissance results and creates targeted follow-up steps. The convergence step waits for whatever investigation steps were created.

### Pattern 3: Investigation with Dynamic Compositions

When the investigation requires operations that don't map to common patterns, the agent can compose handlers dynamically from grammar primitives:

```yaml
steps:
  - name: custom_analysis
    type: standard
    handler:
      composition:
        primitives:
          - type: Acquire
            variant: HttpSource
            config:
              url: "${step_inputs.analysis_endpoint}"
              method: POST
              body: "${step_inputs.analysis_payload}"
          - type: Transform
            variant: FieldExtract
            config:
              source_path: "$.analysis.findings"
          - type: Validate
            variant: SchemaCheck
            config:
              schema_ref: "analysis_result_v1"
          - type: Transform
            variant: Reshape
            config:
              target_shape: "investigation_summary"
        mixins: [WithRetry, WithObservability]
    dependencies:
      - initial_data_gathering
```

The composition is assembled from grammar primitives at task creation time, validated against the grammar's structural invariants (including the single-mutation boundary), and executed with the same guarantees as any common pattern. The agent gets exactly the analysis pipeline it needs without registering a new pattern.

### Pattern 4: Agent-Created Planning Tasks

When the agent wants to use Tasker's LLM planning capabilities (Phase 2) for part of its investigation:

```yaml
name: agent_planned_investigation
namespace_name: agent_research
version: 1.0.0
description: "Agent-initiated task with LLM planning for investigation strategy"

steps:
  - name: gather_context
    type: standard
    handler:
      callable: agent_research.prepare_context
    dependencies: []

  - name: plan_investigation
    type: planning
    handler:
      grammar: planning_step
      config:
        model: claude-sonnet-4-5-20250929
        capability_schema: standard_v1
        max_fragment_steps: 15
        max_fragment_depth: 2
        planning_prompt: |
          Given the gathered context, plan an investigation workflow
          that identifies the information needed to make a decision about
          the original problem. Use http_request for data gathering,
          validate for quality checking, and aggregate for synthesis.
        context_from:
          - gather_context
    dependencies:
      - gather_context

  - name: synthesize_for_agent
    type: deferred
    handler:
      callable: agent_research.package_results
    dependencies:
      - plan_investigation
```

This composes the agent-client pattern with Phase 2's planning interface: the agent creates a task that contains a planning step, and the planning step generates the investigation workflow dynamically. The agent gets the benefit of both its own high-level reasoning (what to investigate) and the LLM planner's tactical reasoning (how to structure the investigation).

---

## The Shared Tooling Foundation

### The `tasker-tooling` Crate

The capabilities that an agent needs at design time — template inspection, schema validation, grammar vocabulary queries, composition validation, code generation — are the same capabilities that `tasker-ctl` provides to human developers through the CLI. Building these capabilities twice (once for CLI, once for MCP) creates maintenance burden and risks behavioral divergence.

The `tasker-tooling` crate extracts the shared logic into a library consumed by both interfaces:

```
tasker-tooling (library crate)
├── template_parser      — Parse and validate TaskTemplate YAML
├── schema_inspector     — Inspect and compare result_schema contracts
├── codegen_engine       — Generate typed handler scaffolds across languages
├── handler_resolver     — Validate handler callable → registration mapping
├── grammar_vocabulary   — Query available primitives, common patterns, composition rules
├── composition_validator — Validate grammar compositions against structural invariants
└── capability_schema    — Derive and query capability schemas from compositions

tasker-ctl (binary crate)
├── CLI argument parsing
├── Terminal output formatting
└── Calls tasker-tooling functions

tasker-mcp (binary crate)
├── MCP protocol handling
├── Tool registration and dispatch
└── Calls tasker-tooling functions
```

**Extraction timing:** The `tasker-tooling` extraction should follow once TAS-280 stabilizes the codegen and validation APIs. Extracting too early risks premature abstraction if the API surface is still shifting. However, the mental model of "these are the same capabilities with different front-ends" should inform the `tasker-ctl` design now so the extraction is straightforward later.

### MCP Server as Agent Interface

The MCP server exposes `tasker-tooling` capabilities as MCP tools. For agent integration, the key tools are:

| Tool | Purpose | Agent Use Case |
|------|---------|---------------|
| `template_inspect` | Return template structure, schemas, dependencies | Agent understanding available workflows |
| `template_validate` | Validate a template for structural correctness | Agent verifying its generated templates |
| `schema_compare` | Check compatibility between step output and input schemas | Agent ensuring data flow correctness |
| `grammar_vocabulary` | List available primitives, their contracts, composition rules | Agent composing handlers from grammar primitives |
| `composition_validate` | Validate a grammar composition against structural invariants | Agent checking compositions before task submission |
| `capability_query` | Query common patterns and primitives by capability (what they do) rather than name | Agent discovering relevant patterns for a problem |
| `template_generate` | Generate a template from structured description | Agent creating investigation templates |

These tools are available to any MCP client — IDE extensions for human developers, agent frameworks, or standalone LLM sessions. The tooling layer doesn't distinguish between clients; it provides capabilities and lets the client use them as appropriate.

---

## Observability for Agent Workflows

### Tracing Agent Reasoning Chains

The `parent_correlation_id` field connects all tasks in an agent's reasoning chain. Standard Tasker telemetry — step timing, results, failures, retries — is emitted for every step in every task. No special agent-aware telemetry is needed.

What *is* needed is the ability to query and visualize across the chain:

- "Show me all tasks with `parent_correlation_id = X`" — the complete reasoning chain
- "What was the total resource consumption across this chain?" — budget accounting
- "Which investigation step took the longest?" — performance analysis
- "What did the convergence step produce?" — investigation results

These are standard queries against existing telemetry, filtered by `parent_correlation_id`. The correlation field is the only mechanism needed; the rest is query design.

### What Tasker Observes vs. What the Agent Observes

There is a clear boundary between what Tasker can observe and what it cannot:

**Tasker observes:**

- Every step's execution: timing, inputs, outputs, retries, failures
- Task lifecycle: creation, progress, completion
- Resource consumption: steps created, time elapsed, cost incurred
- Correlation: `parent_correlation_id` linking related tasks

**Tasker does not observe:**

- The agent's internal reasoning between tasks
- Why the agent chose to create a particular investigation task
- The agent's interpretation of results before creating the next task
- Agent-side failures (network errors calling the API, agent crashes)

This boundary is clean and intentional. Tasker provides infrastructure telemetry. The agent's own reasoning and decision-making is the agent framework's responsibility to observe and debug. The handoff point — task creation and result retrieval — is fully observable on both sides.

### Recommended Agent-Side Practices

While Tasker cannot enforce these, agents interacting with Tasker should:

- Include descriptive metadata in task context explaining *why* this investigation is being conducted
- Use consistent `parent_correlation_id` values across a reasoning chain
- Set appropriate resource bounds on investigation tasks (don't use defaults for research workflows)
- Log their interpretation of investigation results before creating follow-up tasks
- Handle task failures gracefully — a failed investigation task is information, not necessarily a fatal error

---

## What This Is Not

**It is not agent-to-agent communication.** Tasker does not route messages between agents, maintain agent registries, or coordinate agent handoffs. If agents need to communicate, they do so through their own infrastructure. Tasker provides task results, not messaging.

**It is not persistent agent memory.** Tasker does not maintain state across agent sessions. Each task is independent. If an agent needs to remember what it learned from a previous investigation, it maintains that state externally and provides it as task context in subsequent requests.

**It is not autonomous scheduling.** Tasker does not decide when an agent should investigate or what it should investigate. The agent makes those decisions. Tasker executes what the agent requests, with the guarantees the agent needs.

**It is not a "swarm."** The vision is not a swarm of agents coordinating through Tasker. The vision is a thoughtful agent — or a small number of purpose-specific agents — using Tasker's deterministic infrastructure to structure their investigation and execution. The value is not in scale of agents but in the quality of the infrastructure supporting each agent's reasoning.

---

## Relationship to Existing Phases

| Phase | Agent Integration Point |
|-------|------------------------|
| **Phase 0: Foundation** | MCP server provides design-time interface. `tasker-tooling` crate powers both human and agent interactions. Agent can generate templates and validate schemas. |
| **Phase 1: Action Grammars** | Agent can compose handlers from grammar primitives for investigation steps. Grammar vocabulary and common patterns are queryable through MCP tools. |
| **Phase 2: Planning Interface** | Agent can create tasks containing planning steps, combining its high-level reasoning with LLM planning's tactical composition. |
| **Phase 3: Recursive Planning** | Agent-created investigation tasks complement recursive planning — the agent handles task-level decomposition while planning steps handle step-level composition. |
| **Complexity Management** | Agent task chains use existing observability through `parent_correlation_id`. No new telemetry infrastructure needed. |

Agent integration is not "Phase N." It is a capability that emerges from the properties Tasker already has and becomes richer as each phase adds vocabulary and tooling.

---

## Future Considerations

### Research Workflow Template Library

As agents use Tasker for investigation, common patterns will emerge. A library of research workflow templates in `tasker-contrib` — parallel investigation, staged analysis, decision-point-driven deep dives — would reduce the overhead for agents building investigation workflows. These templates would use common grammar patterns and support dynamic composition for custom analysis steps.

### Agent SDK / Client Library

While agents can interact with Tasker through the standard API, a thin client library that encapsulates common patterns (create investigation task, wait for results, parse converged findings) would reduce integration friction. This is a convenience layer, not a new abstraction — it wraps existing API calls in agent-friendly patterns.

### Feedback Loops

Over time, patterns in how agents use investigation results to inform workflow design could feed back into the grammar's common patterns. If agents consistently compose similar handlers for research, those compositions become candidates for named common patterns with additional testing and documentation. If investigation workflows consistently follow certain patterns, those patterns become template library entries. The system learns from its agent clients' behavior, not through agent-internal mechanisms, but through observable patterns in task creation and execution.

---

*This document describes a cross-cutting capability, not a phase. Agent integration composes with all phases of the generative workflow initiative and requires no changes to Tasker's orchestration runtime. It is enabled by existing infrastructure and enriched by each subsequent phase.*
