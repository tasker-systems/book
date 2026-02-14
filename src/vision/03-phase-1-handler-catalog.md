# Phase 1: Handler Catalog

*Generic, composable step handlers as the vocabulary of dynamic workflow planning*

---

## Phase Summary

The handler catalog is a library of parameterized step handlers that perform common operations — HTTP requests, data transformation, schema validation, fan-out decomposition, aggregation, human gating, notification dispatch — without requiring application-specific code. Each handler is configured entirely through `step_inputs` JSONB, making it composable by both human authors and LLM planners.

This phase delivers independent value. Even without LLM integration, composable handlers reduce the boilerplate of workflow authoring and enable a richer template ecosystem in `tasker-contrib`.

---

## Research Areas

### 1. Handler Taxonomy

**Question:** What is the minimal set of generic handlers that covers the majority of workflow patterns?

**Research approach:**

- Audit existing Tasker example workflows and extract recurring patterns
- Survey workflow patterns in competing systems (Airflow operators, Temporal activities, Prefect tasks, Step Functions integrations)
- Categorize by operation type: I/O (fetch/send), computation (transform/validate), control flow (decide/gate/fan-out), aggregation (converge/reduce)

**Proposed initial catalog:**

| Handler | Purpose | Key Parameters |
|---------|---------|----------------|
| `http_request` | Make HTTP calls with configurable auth, headers, retry | URL, method, headers, body template, auth config, response extraction path, expected status codes |
| `transform` | Reshape data between steps | Input mapping (JSONPath/jq-style), output schema, transformation rules |
| `validate` | Validate data against schemas | JSON Schema or custom validation rules, error handling strategy (fail/flag/filter) |
| `fan_out` | Decompose work into parallel batches | Data source reference, partition strategy, worker template, max concurrency |
| `aggregate` | Converge and reduce results from parallel steps | Reduction strategy (merge/concat/custom), failure threshold, output schema |
| `gate` | Human-in-the-loop approval checkpoint | Notification config, approval criteria, timeout behavior, escalation rules |
| `notify` | Dispatch notifications | Channel (webhook/email/slack), template, recipient config |
| `decide` | Nested decision point (can be LLM-backed in Phase 2) | Decision logic config, possible outcomes, routing rules |

**Open questions:**

- Is `transform` one handler or a family? (JSONPath extraction vs. full data reshaping vs. type coercion)
- Should `http_request` handle authentication internally or delegate to a separate `auth` handler?
- How granular should error handling strategies be? Per-handler config vs. workflow-level policy?

### 2. Configuration Schema Design

**Question:** How should handler parameters be structured for both human authoring and LLM generation?

**Research approach:**

- Design configuration schemas using JSON Schema for validation
- Evaluate trade-offs between expressiveness and complexity
- Test with both human authors (can they write configs easily?) and LLM planners (can models generate valid configs?)

**Design principles:**

- **Declarative over imperative.** Configs describe *what*, not *how*. No embedded code, no eval.
- **Schema-validated.** Every handler publishes a JSON Schema for its configuration. Invalid configs are rejected before execution.
- **Defaulted sensibly.** Handlers should work with minimal configuration; advanced options are available but not required.
- **Composable inputs.** Step inputs can reference outputs from upstream steps using a consistent path notation (e.g., `${steps.validate_data.result.valid_records}`).

**Example configuration (http_request):**

```yaml
handler:
  catalog: http_request
  config:
    url: "https://api.example.com/records/${steps.extract_ids.result.record_id}"
    method: POST
    headers:
      Content-Type: application/json
      Authorization: "Bearer ${secrets.api_token}"
    body:
      record_id: "${steps.extract_ids.result.record_id}"
      action: "enrich"
    expected_status: [200, 201]
    response_extract: "$.data.enriched_record"
    retry:
      max_attempts: 3
      backoff: exponential
    timeout_ms: 5000
```

**Open questions:**

- What expression language for input references? JSONPath, jq, a custom DSL, or simple dot-notation?
- How should secrets be referenced? Environment variables, a secret store abstraction, or both?
- Should there be a "dry run" mode where handlers validate their config without executing?

### 3. Capability Schema (Machine-Readable Handler Descriptions)

**Question:** How should handlers describe their capabilities for consumption by LLM planners?

**Research approach:**

- Study function calling / tool use schemas from Claude, OpenAI, and other LLM APIs
- Design a capability description format that serves both as LLM tool descriptions and as human documentation
- Prototype with Claude to validate that the schema enables effective planning

**Capability schema requirements:**

- Handler name and description (natural language for LLM consumption)
- Input parameters with types, constraints, defaults, and descriptions
- Output schema (what the handler produces on success)
- Error modes (what failure looks like, whether retryable)
- Resource requirements (network access needed, approximate latency, cost implications)
- Composability hints (what this handler is typically used with, valid upstream/downstream patterns)

**Example capability description:**

```yaml
name: http_request
description: >
  Makes an HTTP request to an external service. Supports GET, POST, PUT, PATCH, DELETE.
  Extracts specified fields from the response. Handles authentication, retries, and timeouts.
  Use for API integrations, data fetching, webhook dispatch, and service-to-service communication.

inputs:
  url:
    type: string
    required: true
    description: "Target URL. May include ${step_reference} interpolations."
  method:
    type: enum
    values: [GET, POST, PUT, PATCH, DELETE]
    default: GET
  body:
    type: object
    required_when: "method in [POST, PUT, PATCH]"
    description: "Request body. Supports ${step_reference} interpolation in values."
  response_extract:
    type: string
    description: "JSONPath expression to extract from response body."
  # ... additional parameters

outputs:
  status_code: { type: integer }
  response_body: { type: object, description: "Full response or extracted subset" }
  latency_ms: { type: integer }

errors:
  - type: timeout
    retryable: true
    description: "Request exceeded timeout_ms"
  - type: unexpected_status
    retryable: false
    description: "Response status not in expected_status list"

resource_hints:
  requires_network: true
  typical_latency_ms: 100-5000
  idempotent_methods: [GET, PUT, DELETE]
```

**Open questions:**

- How much semantic information does the LLM need to plan effectively? Too little and planning is unreliable; too much and the context window fills up.
- Should capability schemas include example compositions? (e.g., "http_request → validate → transform is a common pattern")
- How do we version capability schemas as handlers evolve?

### 4. Inter-Step Data Flow

**Question:** How do handler outputs flow as inputs to downstream handlers?

**Research approach:**

- Audit current `dependency_results` access patterns in existing workers
- Design a consistent data flow mechanism that works with both static and dynamic workflows
- Evaluate whether current `workflow_steps.results` JSONB storage is sufficient or needs extension

**Design considerations:**

- Today, handlers access upstream results through `context.get_dependency_result(step_name)`. This works for static workflows where step names are known.
- In dynamically planned workflows, step names may be generated by the planner. The data flow mechanism needs to support referencing by name (which the planner assigns) or by position in the dependency graph.
- Large intermediate results (files, datasets) should not flow through the database. Consider a reference-based pattern where handlers store large results in object storage and pass references through the step result.
- Schema validation at the boundary: should a handler's output schema be validated before it's stored, ensuring downstream handlers receive conformant inputs?

---

## Prototyping Goals

### Prototype 1: Basic Catalog Handlers

**Objective:** Implement `http_request`, `transform`, and `validate` handlers in Rust, demonstrating configuration-driven execution.

**Success criteria:**

- A task template using only catalog handlers can be authored in YAML
- Handlers execute correctly with parameterized configurations
- Error handling (timeouts, validation failures, unexpected responses) works as configured
- Handlers are registered in a catalog worker that subscribes to a dedicated namespace

### Prototype 2: Capability Schema Generation

**Objective:** Generate capability schemas from handler implementations and validate they enable LLM planning.

**Success criteria:**

- Capability schemas can be derived (at least partially) from handler configuration schemas
- Claude can generate valid handler configurations when provided with capability schemas
- Generated configurations pass schema validation

### Prototype 3: Cross-Language Catalog Workers

**Objective:** Validate that catalog handlers work across the polyglot worker ecosystem.

**Success criteria:**

- Catalog handlers can be implemented in Rust, Ruby, Python, and TypeScript
- Configuration schema is language-agnostic
- Catalog workers in any language can execute catalog handler steps

---

## Validation Criteria for Phase Completion

1. ✅ At least 5 catalog handlers implemented and tested (recommend: `http_request`, `transform`, `validate`, `gate`, `notify`)
2. ✅ Configuration schemas published as JSON Schema for all handlers
3. ✅ Capability schemas published for all handlers in a format suitable for LLM consumption
4. ✅ A catalog worker deployment exists that registers all standard handlers
5. ✅ At least 3 example workflows authored using only catalog handlers (no custom code)
6. ✅ Documentation in `tasker-contrib` covering handler usage, configuration, and extension patterns
7. ✅ Inter-step data flow works correctly with catalog handlers in both static and conditional workflows

---

## Relationship to Other Phases

- **Phase 2** depends on this phase: the planning interface generates workflow fragments that reference catalog handlers.
- **Phase 3** builds on this phase: catalog handlers are the compilation targets for WASM sandboxing.
- **Phase 4** uses this phase: recursive planning composes catalog handlers across multiple planning phases.
- This phase is **independently valuable** regardless of whether subsequent phases are implemented.

---

*This document will be updated as research progresses and prototyping reveals design insights.*
