# Phase 2: Planning Interface

*LLM-backed planning steps and workflow fragment generation*

---

## Phase Summary

The planning interface introduces a new step handler type — the planning step — that uses an LLM to generate workflow fragments from problem descriptions and capability schemas. The orchestration layer validates these fragments against the handler catalog and materializes them through the existing transactional step creation infrastructure.

This is the phase where probabilistic planning meets deterministic execution. The contract is: given context and capabilities, produce a valid plan. The system validates and executes. The LLM reasons; the system guarantees.

---

## Research Areas

### 1. Workflow Fragment Schema

**Question:** What is the structural representation of a workflow fragment that a planning step produces?

**Research approach:**

- Start from the existing `DecisionPointOutcome::CreateSteps { step_names }` and extend it to carry full step specifications
- Evaluate what minimum information is needed to materialize a step (handler reference, inputs, dependencies, configuration)
- Design for validation: the schema should make it structurally impossible to express certain invalid states

**Proposed fragment structure:**

```json
{
  "fragment_version": "1.0",
  "planning_context": {
    "goal": "Process and enrich customer records from CSV upload",
    "reasoning": "The dataset contains 5000 records requiring validation, API enrichment, and categorization...",
    "estimated_steps": 7,
    "estimated_depth": 3
  },
  "steps": [
    {
      "name": "validate_records",
      "handler": {
        "catalog": "validate",
        "config": {
          "schema": { "$ref": "customer_record_v2" },
          "on_invalid": "flag"
        }
      },
      "dependencies": [],
      "inputs": {
        "data": "${task.context.uploaded_records}"
      }
    },
    {
      "name": "enrich_valid",
      "handler": {
        "catalog": "http_request",
        "config": {
          "url": "https://enrichment-api.example.com/v2/enrich",
          "method": "POST",
          "body": { "records": "${steps.validate_records.result.valid_records}" }
        }
      },
      "dependencies": ["validate_records"]
    },
    {
      "name": "categorize",
      "handler": {
        "catalog": "decide",
        "config": {
          "type": "planning_step",
          "context_from": ["enrich_valid"],
          "capability_schema": "standard_v1",
          "prompt": "Based on the enriched records, determine optimal categorization workflow"
        }
      },
      "dependencies": ["enrich_valid"],
      "step_type": "decision"
    },
    {
      "name": "converge_results",
      "handler": {
        "catalog": "aggregate",
        "config": {
          "strategy": "merge",
          "output_key": "final_results"
        }
      },
      "dependencies": ["categorize"],
      "step_type": "deferred"
    }
  ],
  "convergence": "converge_results",
  "resource_bounds": {
    "max_downstream_steps": 15,
    "max_downstream_depth": 2
  }
}
```

**Open questions:**

- Should fragments be expressed in JSON, YAML, or a purpose-built DSL? JSON is LLM-native but verbose; YAML is more readable but harder to validate precisely.
- How should fragments reference the planning step's own results? The planning step creates downstream steps, but those steps need to reference data that existed before planning.
- Should fragments support conditional sub-paths, or should every conditional branch require a nested planning step?
- How do we handle fragments that reference both catalog handlers and application-specific handlers?

### 2. Fragment Validation Pipeline

**Question:** What validations must pass before a fragment is materialized?

**Research approach:**

- Enumerate all failure modes of an invalid fragment
- Design a validation pipeline that catches errors early with actionable diagnostics
- Consider whether validation should be strict (reject anything questionable) or lenient (accept with warnings)

**Proposed validation stages:**

| Stage | Validates | Failure Mode |
|-------|-----------|--------------|
| **Schema validation** | Fragment structure conforms to fragment schema | Malformed fragment — parsing error |
| **Handler reference check** | Every `handler.catalog` reference exists in the registered catalog | Unknown handler — planner hallucinated a capability |
| **Configuration validation** | Handler config matches the handler's configuration JSON Schema | Invalid config — wrong types, missing required fields |
| **DAG validation** | Dependencies form a valid acyclic graph | Cycle detected, orphan steps, unreachable convergence |
| **Input reference resolution** | All `${step_reference}` paths resolve to steps in the fragment or existing task context | Dangling reference — step references nonexistent upstream |
| **Resource bound check** | Total steps, depth, fan-out factor within configured limits | Plan exceeds bounds — too large, too deep, too expensive |
| **Convergence validation** | Deferred steps have valid intersection semantics with fragment steps | Convergence cannot resolve — no path to terminal state |

**Open questions:**

- Should validation be a single pass or multi-pass? (Early termination vs. collecting all errors)
- Should the planner receive validation feedback and be able to revise? (Planning → validate → revise loop)
- What diagnostic information should be stored when a fragment fails validation? (For observability and planner improvement)
- Should there be a "simulation" mode that validates and reports without materializing?

### 3. LLM Integration Adapter

**Question:** How should the planning step interface with LLM APIs?

**Research approach:**

- Design an adapter pattern that supports multiple LLM providers
- Study prompt engineering patterns for structured output generation (function calling, JSON mode, schema-constrained generation)
- Evaluate context window management strategies for large capability schemas

**Design considerations:**

**Provider abstraction:** The planning step should not be coupled to a specific LLM API. An adapter interface should support at minimum Claude (Anthropic API) and OpenAI-compatible endpoints, with the ability to add providers.

**Prompt construction:** The planning prompt has several components:

- System context: "You are a workflow planner. Generate a workflow fragment using the available handlers."
- Capability schema: Machine-readable descriptions of available handlers (from Phase 1)
- Task context: The problem description, input data schema, and any accumulated results
- Planning constraints: Resource bounds, required convergence points, any domain-specific rules
- Output format: The fragment schema with examples

**Context window management:** Capability schemas can be large. Strategies include:

- Include only handler summaries in the initial prompt; fetch full schemas for handlers the LLM selects
- Hierarchically organize handlers by category; include category-level descriptions initially
- Use few-shot examples that demonstrate the most common compositions

**Structured output:** Use function calling / tool use APIs where available to constrain the LLM's output to valid fragment structures. Fall back to JSON mode with post-hoc validation where function calling isn't supported.

**Open questions:**

- How many planning attempts should be allowed before failing? (One shot? Up to 3 with validation feedback?)
- Should the planning step cache successful plans for similar problem descriptions?
- How should model selection work? (Configurable per planning step? Global default with overrides?)
- What telemetry should be emitted from the LLM call? (Token counts, latency, planning reasoning)

### 4. Fragment Materialization

**Question:** How does a validated fragment become real workflow steps?

**Research approach:**

- Study the existing `ResultProcessingService` path for decision point outcomes
- Determine what modifications are needed to support full step specifications (not just step names)
- Validate transactional guarantees are preserved with richer creation payloads

**Design considerations:**

The current flow for decision points is:

1. Decision handler returns `DecisionPointOutcome::CreateSteps { step_names }`
2. `ResultProcessingService` validates step names exist in the template
3. Steps are created from template definitions in a single transaction
4. Edges are created connecting the decision step to new steps
5. New steps are enqueued

For planning steps, the flow extends to:

1. Planning handler returns a validated workflow fragment
2. Fragment materialization service creates steps from fragment specifications (not template)
3. Steps are created with handler references, configurations, and inputs in a single transaction
4. Edges are created from the fragment's dependency declarations
5. New steps are enqueued for the appropriate namespace

The key difference: instead of looking up step definitions in a template, the materialization service uses the fragment's step specifications directly. This requires that the catalog worker's namespace is known at materialization time, so steps can be routed to the correct queue.

**Open questions:**

- Should fragment materialization be a separate service or an extension of `ResultProcessingService`?
- How should the planning step's own task template relate to the materialized fragment? Is it a "meta-template" that declares the planning step and convergence, with the middle filled in dynamically?
- What happens if materialization fails after partial creation? (Transaction should handle this, but worth explicit validation)

### 5. The Planning Step Template Pattern

**Question:** What does a task template look like when it includes planning steps?

**Research approach:**

- Design a template pattern that clearly separates static structure (planning step, convergence) from dynamic content (planned fragment)
- Validate that existing template validation can accommodate planning steps
- Test with real problem descriptions to evaluate ergonomics

**Proposed template pattern:**

```yaml
name: adaptive_data_processing
namespace_name: dynamic_planning
version: 1.0.0
description: Process data with LLM-planned workflow

handler_catalog: standard_v1

steps:
  - name: ingest_data
    type: standard
    handler:
      callable: DataIngestionHandler  # Application-specific
    dependencies: []

  - name: plan_processing
    type: planning  # New step type
    handler:
      catalog: planning_step
      config:
        model: claude-sonnet-4-5-20250929
        capability_schema: standard_v1
        max_fragment_steps: 20
        max_fragment_depth: 3
        planning_prompt: |
          Given the ingested data characteristics, plan a processing
          workflow that validates, enriches, and categorizes the records.
        context_from:
          - ingest_data
    dependencies:
      - ingest_data

  - name: finalize
    type: deferred
    handler:
      callable: FinalizationHandler  # Application-specific
    dependencies:
      - plan_processing  # Intersection semantics with planned steps
```

**Key insight:** The template defines the *frame* — what happens before planning and what happens after convergence. The middle is filled in by the planner. This preserves the template's role as a structural contract while enabling dynamic topology.

---

## Prototyping Goals

### Prototype 1: Fragment Schema and Validation

**Objective:** Define the fragment schema and implement the validation pipeline, independent of LLM integration.

**Success criteria:**

- Fragment schema defined with JSON Schema
- Validation pipeline rejects all identified invalid fragment patterns
- Validation produces actionable diagnostic messages
- Valid fragments can be materialized into workflow steps in a test environment

### Prototype 2: LLM-Generated Fragments

**Objective:** Validate that an LLM can generate valid workflow fragments from capability schemas.

**Success criteria:**

- Claude generates valid fragments for at least 3 distinct problem types
- Generated fragments pass the validation pipeline
- Fragments use catalog handlers appropriately (correct handler selection, valid configurations)
- Planning prompt engineering produces consistent results across problem descriptions

### Prototype 3: End-to-End Planning and Execution

**Objective:** Execute a complete workflow with an LLM planning step.

**Success criteria:**

- Task is created with a planning step in its template
- Planning step calls LLM, receives fragment, passes validation
- Fragment is materialized as workflow steps
- Planned steps execute through catalog workers
- Convergence step receives results from planned steps
- Full workflow observable through standard Tasker telemetry

---

## Validation Criteria for Phase Completion

1. ✅ Workflow fragment schema defined and documented
2. ✅ Fragment validation pipeline implemented with all stages described above
3. ✅ Planning step handler type implemented in at least Rust
4. ✅ LLM integration adapter supports at least one provider (recommend: Anthropic API)
5. ✅ Fragment materialization extends existing step creation with full transactional guarantees
6. ✅ At least 3 end-to-end workflows demonstrated with LLM planning
7. ✅ Validation failure modes tested and documented with diagnostic output
8. ✅ Planning step telemetry includes LLM call metrics, fragment structure, and validation results

---

## Relationship to Other Phases

- **Phase 1** is a prerequisite: planning steps generate fragments that reference catalog handlers.
- **Phase 3** enhances this phase: WASM sandboxing provides stronger isolation for planned handler execution.
- **Phase 4** extends this phase: recursive planning is nested planning steps within planned fragments.

---

*This document will be updated as Phase 1 progresses and reveals design insights that inform planning interface design.*
