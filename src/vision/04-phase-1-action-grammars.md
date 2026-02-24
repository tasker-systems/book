# Phase 1: Action Grammars

*Rust-native composable `action(resource)` primitives as the vocabulary of generative workflow planning*

---

## Phase Summary

The action grammar is a framework of composable, Rust-native `action(resource)` primitives with compile-time enforced data contracts. Each primitive is a verb applied to a typed resource — `Acquire(HttpEndpoint)`, `Transform(JsonPayload)`, `Validate(Schema)`, `Persist(DatabaseRow)` — with declared input and output types that the Rust compiler verifies.

The fundamental unit of composition is the **handler**: a chain of `action(resource)` primitives assembled to perform a business-meaningful operation. All handlers — whether referenced by name from a common patterns library or composed on the fly by an LLM planner — are validated and executed through the same pipeline. There is one composition model, one validation path, one execution path.

The grammar's central safety invariant is the **single-mutation boundary**. A valid composition may contain an arbitrary number of non-mutating actions (reads, transforms, validations, calculations) but has **at most one external mutation** (a create, update, or delete against a database, API, or other external system). Everything before the mutation is preparatory, idempotent, and safely retryable. The mutation is the commitment point. Nothing after it should be fallible in a way that triggers re-execution of the mutation. This structural rule — enforced at assembly time — is what makes compositions safe regardless of how they were assembled.

This phase delivers independent value. Even without LLM integration, composable handlers reduce the boilerplate of workflow authoring, provide stronger correctness guarantees than hand-written handlers, and enable a richer template ecosystem in `tasker-contrib`. The action grammar layer also provides the vocabulary that Phase 2's LLM planner and agent clients compose from — a vocabulary that is open, safe, and never artificially limited.

---

## Research Areas

### 1. Action Grammar Primitives

**Question:** What are the fundamental verbs of workflow action, and how do they differ from handlers?

**The distinction:** A primitive is a single `action(resource)` with compile-time enforced input/output contracts. A handler composes primitives into a business-meaningful operation. The primitive is the atom; the handler is the molecule.

**Research approach:**

- Audit existing Tasker example workflows and extract recurring low-level actions
- Analyze Phase 0 MCP server usage patterns to identify what compositions developers actually request
- Survey workflow primitives in competing systems (Airflow operators, Temporal activities, Prefect tasks, Step Functions integrations) at a lower granularity than their handler-level abstractions
- Categorize by action type: non-mutating (reads, transforms, validations, control flow) vs. mutating (external state changes)

**Proposed primitive taxonomy:**

*Non-mutating primitives (idempotent, retryable, no external side effects):*

| Primitive | Concern | Input Contract | Output Contract |
|-----------|---------|---------------|----------------|
| `Acquire` | Fetch data from an external source | Source descriptor (URL, query, config) | Raw acquired data + metadata (status, timing) |
| `Transform` | Reshape data from one form to another | Input data + transformation spec | Transformed data conforming to target shape |
| `Validate` | Assert invariants on data | Data + validation rules | Partitioned results (valid set, invalid set, diagnostics) |
| `Gate` | Block execution pending a condition | Gate condition + notification config | Approval/rejection + gating metadata |
| `Decide` | Evaluate conditions and select a path | Decision context + routing rules | Selected path identifier + reasoning |
| `FanOut` | Decompose work into parallel units | Data source + partitioning strategy | Partition descriptors for parallel execution |
| `Aggregate` | Converge and reduce parallel results | Collection of results + reduction strategy | Reduced result conforming to output shape |

*Mutating primitives (external side effects — at most one per composition):*

| Primitive | Concern | Input Contract | Output Contract |
|-----------|---------|---------------|----------------|
| `Persist` | Write state to an external system (database, API, message queue) | Data + destination descriptor + operation (create/update/delete) | Confirmation + metadata (id, version, timestamp) |
| `Emit` | Send a notification or event to an external channel | Data + channel descriptor (webhook, email, queue) | Delivery confirmation + metadata |

The separation between non-mutating and mutating primitives is the grammar's most important structural distinction. Non-mutating primitives can appear in any quantity and any order. Mutating primitives are the composition's commitment point — the single-mutation boundary.

**How primitives differ from existing handlers:**

Today, an `http_request` handler is monolithic — it handles URL construction, authentication, request execution, error handling, response extraction, and output shaping in a single implementation. As a grammar composition, the same operation would be:

```
Acquire(HttpSource { url, method, auth, headers })
  → Transform(ExtractFields { path: "$.data.records" })
  → Validate(JsonSchema { schema: record_schema_v2 })
```

Each step in the composition has typed inputs and outputs. The `Acquire` primitive's output type matches the `Transform` primitive's input type. The compiler verifies this. If someone changes the `Acquire` output shape, compositions that depend on the old shape fail to compile — not at runtime, but at build time.

**Open questions:**

- Is `Transform` one primitive or a family? (Field extraction vs. full reshaping vs. type coercion may warrant separate primitives with different type constraints.)
- Should `Acquire` and `Emit` be symmetric primitives, or does the I/O direction warrant different type signatures?
- How granular should error handling be? Per-primitive error types vs. a unified error model that compositions inherit?
- Should there be a `Cache` primitive for memoizing expensive acquisitions?

### 2. Data Contracts as Compositional Glue

**Question:** How do Rust's type system features enforce correctness of grammar compositions?

**Research approach:**

- Design trait bounds that express "primitive A's output is compatible with primitive B's input"
- Evaluate generic associated types, trait objects, and enum dispatch for composition flexibility
- Prototype compositions and validate that the compiler catches invalid ones
- Design the `dyn Pluggable` boundary for plugin extensibility and runtime composition

**The type-level composition model:**

```rust
/// Every grammar primitive declares its input and output types
trait ActionPrimitive {
    type Input: ActionData;
    type Output: ActionData;
    type Error: ActionError;

    fn execute(&self, input: Self::Input) -> Result<Self::Output, Self::Error>;
}

/// Data contracts: marker trait for types that can flow between primitives
trait ActionData: Serialize + DeserializeOwned + Send + Sync + Debug {}

/// A composition is valid when Output of A matches Input of B
struct Compose<A, B>
where
    A: ActionPrimitive,
    B: ActionPrimitive<Input = A::Output>,
{
    first: A,
    second: B,
}
```

The key insight: `B: ActionPrimitive<Input = A::Output>` is a compile-time constraint. If `A` produces `HttpResponse` and `B` expects `ValidatedRecords`, the composition fails to compile. No runtime surprises.

**The runtime composition boundary:**

All handler compositions — whether referencing common patterns by name or assembled dynamically — pass through a runtime composition boundary where contracts are validated through JSON Schema matching. This is the `dyn Pluggable` boundary: a trait object interface that allows runtime dispatch while still requiring data contracts to be declared:

```rust
/// All composed handlers declare their contracts and dispatch dynamically
trait PluggablePrimitive: Send + Sync {
    fn input_schema(&self) -> &JsonSchema;
    fn output_schema(&self) -> &JsonSchema;
    fn is_mutating(&self) -> bool;  // Single-mutation boundary enforcement
    fn execute(&self, input: serde_json::Value) -> Result<serde_json::Value, ActionError>;
}
```

At the composition boundary, contracts are validated at assembly time through JSON Schema matching. The grammar primitives themselves are compiled Rust with full type safety. The composition layer validates that contracts chain correctly, the single-mutation boundary is respected, and configurations are well-formed — all before any execution occurs. Organization-specific primitives, user-defined transformations, and integration-specific adapters all go through this same boundary.

**Open questions:**

- How do we handle optional fields in data contracts? (A transform that adds fields to its input — the output is a superset of the input type.)
- Should compositions be linear (A → B → C) or support branching (A → B + C → D)?
- How do we express that a primitive preserves certain fields while transforming others? (Partial type transformations are hard to express statically.)
- What is the right balance between static composition (maximum safety, less flexibility) and dynamic dispatch (more flexibility, weaker guarantees)?

### 3. Composition Rules

**Question:** How do primitives combine into handlers while preserving idempotency, single responsibility, and retryability?

**Research approach:**

- Define which compositions are valid from an execution-guarantee perspective (not just type compatibility)
- Formalize the single-mutation boundary as a structural invariant
- Design the mixin/layering approach for building handlers from primitives
- Validate that composed handlers maintain the step contract (idempotent, retryable, side-effect bounded)

**The single-mutation boundary — the central safety invariant:**

A valid composition follows this structural pattern:

```
[non-mutating actions]* → [mutation]? → [non-failing actions]*
```

- **Before the mutation:** An arbitrary chain of `Acquire`, `Transform`, `Validate`, `Decide`, `Aggregate` primitives. All non-mutating, all idempotent, all safely retryable. If the step fails anywhere in this phase, the entire composition can be retried from the beginning with no side effects.
- **The mutation (at most one):** A single `Persist` or `Emit` that commits the composition's external effect. This is the commitment point. Tasker's existing step state machine tracks whether the mutation has occurred.
- **After the mutation:** Only actions that cannot fail in a way that would trigger re-execution of the mutation. Typically: metadata recording, confirmation formatting, non-critical logging.

This rule is what makes compositions safe. It is checkable at assembly time — the grammar knows which primitives are mutating (`is_mutating() == true`) and can enforce that at most one appears, and that it appears in the correct position. A composition that violates the single-mutation boundary is rejected before execution.

**Composition properties preserved by this structure:**

| Property | How the Grammar Enforces It |
|----------|----------------------------|
| **Idempotency** | Non-mutating phase is inherently idempotent. The mutation primitive declares its own idempotency strategy (idempotency keys, conditional execution). Nothing after the mutation can trigger retry. |
| **Retryability** | Re-execution from the beginning replays only idempotent actions until the mutation boundary. The step state machine prevents re-execution of the mutation itself. |
| **Single responsibility** | A composition's responsibility is the business action it represents. One mutation = one externally visible effect. |
| **Side-effect boundary** | The mutation is the composition's only external side effect. It is explicit, bounded, and singular. |

**The mixin approach:**

Handlers are not just linear chains of primitives. They are layered compositions where cross-cutting concerns (error handling, retry logic, observability, caching) are applied as mixins that wrap the core primitive chain:

```
Handler = WithRetry(
    WithObservability(
        WithErrorMapping(
            Acquire → Transform → Validate
        )
    )
)
```

Each mixin layer is itself a primitive (or primitive wrapper) with typed input/output contracts. The mixin transforms the error type, adds metadata to the output, or wraps the execution with retry logic — all type-checked at compile time.

**Open questions:**

- Should the composition framework enforce a maximum depth? (Deep compositions may have unclear failure modes.)
- How should partial failure work? (If Transform succeeds but Validate fails, what is the composition's state?)
- Should compositions support checkpointing? (Resume from the last successful primitive rather than restarting the entire composition.)
- How do we test compositions? (Unit test each primitive independently; integration test the composition. But what about the mixin layers?)

### 4. Handler Composition and Validation

**Question:** How are handlers assembled from grammar primitives, and what validation ensures they are safe to execute?

All handler composition — whether referencing a common pattern by name or assembled dynamically by an LLM or agent — goes through the same pipeline: specification, validation, execution. There is one composition model.

**Research approach:**

- Design a specification format for handler compositions (primitives, configuration, data mappings)
- Build a validation pipeline that checks composition correctness including the single-mutation boundary
- Prototype handler execution through the grammar worker infrastructure
- Evaluate performance characteristics of the validation pipeline

**The handler composition specification:**

A handler is described as a composition of `action(resource)` grammar primitives with configuration and data mappings:

```json
{
  "primitives": [
    {
      "type": "Acquire",
      "variant": "HttpSource",
      "config": {
        "url": "https://api.example.com/v2/search",
        "method": "POST",
        "auth": { "type": "bearer", "token_source": "env:API_KEY" }
      }
    },
    {
      "type": "Transform",
      "variant": "FieldExtract",
      "config": {
        "source_path": "$.response.results",
        "target_shape": "array<SearchResult>"
      },
      "input_mapping": {
        "data": "$.previous.acquired_data"
      }
    },
    {
      "type": "Validate",
      "variant": "SchemaCheck",
      "config": {
        "schema_ref": "search_result_v1",
        "on_invalid": "partition"
      },
      "input_mapping": {
        "data": "$.previous.transformed_data"
      }
    }
  ],
  "mixins": ["WithRetry", "WithObservability"]
}
```

Common patterns — like `http_request` — are named composition specifications that resolve to this same format. Referencing `"pattern": "http_request"` with parameters is syntactic sugar for the fully-specified composition. At execution time, everything is a validated composition of grammar primitives.

**N-intersecting logical actions:**

Compositions are not limited to linear chains. A composition can express intersecting actions — primitives that share data flows and coordination points without being strictly sequential:

- Acquire from multiple sources, then Transform the merged result
- Validate before *and* after a Transform
- Transform into multiple shapes for different downstream consumers
- Acquire and Validate in parallel, then Gate on the combined result

The composition specification supports these patterns through explicit input mappings — each primitive declares where its input comes from, which may be the output of any prior primitive in the composition (not just the immediately preceding one). The validation pipeline verifies that all input mappings resolve to available data with compatible shapes.

**The validation pipeline:**

Every composition passes through the same validation before execution:

1. **Primitive existence check:** Every referenced primitive type and variant exists in the grammar
2. **Configuration validation:** Each primitive's config matches its declared configuration schema
3. **Input mapping resolution:** Every `input_mapping` path resolves to a primitive output in the composition
4. **Contract compatibility:** Output schema of the source primitive is compatible with input schema of the consuming primitive
5. **Single-mutation boundary:** At most one mutating primitive (`Persist`, `Emit`) appears in the composition, and it appears after all fallible preparatory work
6. **Mixin applicability:** Declared mixins are compatible with the composition's primitive chain

This pipeline runs at assembly time — before any execution occurs. An invalid composition is rejected with diagnostic information. The grammar primitives themselves are compiled Rust with full type safety; the validation pipeline ensures that *compositions of those primitives* respect the structural invariants that make them safe.

**Capability schema derivation:**

Because handlers are compositions of typed primitives, their capability schemas can be *derived* from the composition rather than hand-authored. The input contract is the first primitive's input type, parameterized by the handler's configuration. The output contract is the last primitive's output type (or the mutation primitive's confirmation type). The error modes are the union of each primitive's error types. This derivation is mechanistic and always accurate — the capability schema cannot drift from the implementation because it is generated from the same type definitions.

Any client (LLM planner, agent, MCP tool) can inspect what a handler composition will accept and produce before it executes.

**Open questions:**

- Should composition specifications support conditional primitives? (If condition X, include Validate; otherwise skip.)
- How should specifications express branching compositions? (Multiple output paths from a single primitive.)
- Should the MCP server / `tasker-ctl` provide a `compose` command that helps build handler specifications interactively?
- How should error modes be derived for compositions with non-linear data flows?
- How should compositions with zero mutations (pure-read handlers) be distinguished from compositions where the mutation was accidentally omitted?

### 5. Common Patterns Library

**Question:** What does the library of named, documented composition patterns look like, and how does it serve developers and planners?

The common patterns library is a collection of named, well-tested, documented handler composition specifications. It is a **documentation and convenience layer**, not a distinct runtime concept. Every pattern resolves to a standard grammar composition at execution time.

**Research approach:**

- Identify recurring composition patterns from Phase 0 MCP server usage and existing Tasker workflows
- Design a pattern specification format that is both human-readable and machine-consumable
- Validate that patterns are discoverable by LLM planners through capability schemas

**Pattern specification:**

Each pattern is a named, parameterized composition specification:

```yaml
name: http_request
description: >
  Makes an HTTP request to an external service with configurable authentication,
  error handling, and response extraction. Composed from Acquire + Transform + Validate
  primitives with retry and observability mixins.

composition:
  - Acquire(HttpSource)
  - Transform(ResponseExtract)
  - Validate(StatusCodeCheck)
  mixins: [WithRetry, WithObservability, WithTimeout]

parameters:
  url: { type: string, required: true }
  method: { type: enum, values: [GET, POST, PUT, PATCH, DELETE], default: GET }
  headers: { type: map, default: {} }
  body: { type: object, required_when: "method in [POST, PUT, PATCH]" }
  auth: { type: AuthConfig, default: none }
  response_extract: { type: string, description: "JSONPath for response extraction" }
  expected_status: { type: array, default: [200] }
  timeout_ms: { type: integer, default: 5000 }
  retry: { type: RetryConfig, default: { max_attempts: 3, backoff: exponential } }

# Derived from composition types — not hand-authored
input_contract: HttpRequestInput
output_contract: HttpRequestOutput
error_modes:
  - { type: timeout, retryable: true, source: Acquire }
  - { type: unexpected_status, retryable: false, source: Validate }
  - { type: extraction_failed, retryable: false, source: Transform }
```

When a template references `"pattern": "http_request"` with parameters, the system resolves the pattern to a composition specification, applies the parameters, and validates through the standard pipeline. The pattern is a shorthand, not a different execution path.

**Proposed initial patterns:**

| Pattern | Composition | Key Parameters |
|---------|-------------|----------------|
| `http_request` | Acquire(Http) → Transform(Extract) → Validate(Status) | URL, method, headers, body, auth, extraction path |
| `transform` | Transform(Reshape) | Input mapping, output schema, transformation rules |
| `validate` | Validate(Schema) | JSON Schema, error strategy (fail/flag/filter) |
| `fan_out` | FanOut(Partition) | Data source, partition strategy, max concurrency |
| `aggregate` | Aggregate(Reduce) | Reduction strategy, failure threshold, output schema |
| `gate` | Gate(Approval) → Emit(Notification) | Notification config, approval criteria, timeout |
| `notify` | Emit(Channel) | Channel type (webhook/email/slack), template, recipients |
| `decide` | Decide(Rules) | Decision logic config, possible outcomes, routing rules |
| `persist` | Validate(PreCheck) → Persist(Target) | Target system, operation, idempotency key |

**Open questions:**

- Should patterns support versioning? (Upgrading a composition without breaking existing templates.)
- How should organization-specific patterns be registered alongside standard ones?
- Should a pattern's composition be directly inspectable by clients? (Useful for LLMs that want to understand what a pattern does before using it, and for agents building modified compositions from a pattern as a starting point.)

### 6. FFI Surface for Polyglot Consumption

**Question:** How do Python, Ruby, and TypeScript developers use Rust-implemented action grammars?

**Research approach:**

- Design the boundary between Rust grammar layer and polyglot developer layer
- Evaluate whether polyglot developers interact with grammar primitives directly or only through composed handlers
- Prototype FFI bindings for grammar handler invocation

**Design principle:** Polyglot developers should not need to understand Rust. They interact with action grammars through three paths:

**Path 1: Configuration-driven pattern usage.** A developer references a common pattern in their task template YAML. The handler executes in the Rust grammar worker. No language-specific code needed:

```yaml
steps:
  - name: fetch_records
    handler:
      pattern: http_request
      config:
        url: "https://api.example.com/records"
        method: GET
        response_extract: "$.data"
```

**Path 2: Language-specific DSL wrappers.** For developers who want to use grammar primitives alongside their own business logic in the same step, thin FFI wrappers expose primitives through each language's DSL:

```python
@step_handler("enrich_and_validate")
@depends_on(records="fetch_records")
def enrich_and_validate(records, context):
    # Use grammar primitives through FFI wrapper
    validated = context.grammar.validate(records, schema="record_v2")
    enriched = context.grammar.http_request(
        url="https://enrichment.example.com/v2/enrich",
        method="POST",
        body={"records": validated.valid_records}
    )
    return {"enriched": enriched, "invalid": validated.invalid_records}
```

**Path 3: Composition specification.** For agents, LLM planners, and any client that prefers structured data over code, handler compositions are specified as JSON and executed through the grammar worker infrastructure without any language-specific code. This is the primary path for dynamic composition.

The FFI wrapper handles serialization/deserialization across the language boundary. The Rust grammar layer executes the primitive with full type checking. The developer gets the safety of the grammar without leaving their language.

**Open questions:**

- Should FFI wrappers expose individual primitives or only composed handlers?
- What is the serialization overhead of crossing the FFI boundary for each primitive call? (May need batching or composition-level FFI rather than primitive-level.)
- How should errors from Rust grammar execution be translated to language-idiomatic exceptions?
- Should there be a "local grammar worker" mode where handlers execute in-process rather than through queue dispatch?

---

## Prototyping Goals

### Prototype 1: Primitive Framework and Basic Compositions

**Objective:** Implement the `ActionPrimitive` trait system, `Acquire`, `Transform`, and `Validate` primitives, and demonstrate composition with compile-time type checking.

**Success criteria:**

- Primitive trait with associated Input/Output types compiles and works
- Valid compositions compile; invalid compositions (type mismatch) fail to compile with clear error messages
- A simple composition (Acquire → Transform → Validate) executes correctly with test data
- Mixin wrappers (WithRetry, WithObservability) compose with core primitives

### Prototype 2: Composition Validation and the Single-Mutation Boundary

**Objective:** Demonstrate the validation pipeline, including single-mutation boundary enforcement, contract checking, and diagnostic output for invalid compositions.

**Success criteria:**

- Validation catches incompatible primitive chains (output/input mismatch)
- Validation catches invalid configurations (missing required fields, wrong types)
- Validation rejects compositions with multiple mutating primitives
- Validation rejects compositions where fallible actions follow the mutation
- Invalid compositions produce actionable diagnostic messages
- Valid compositions execute through the grammar worker with correct lifecycle

### Prototype 3: Common Pattern Resolution and Execution

**Objective:** Build the `http_request` common pattern and demonstrate that named pattern references resolve to standard compositions.

**Success criteria:**

- `http_request` pattern assembled from Acquire(Http) → Transform(Extract) → Validate(Status)
- Pattern reference with parameters resolves to a composition specification
- Resolved composition passes the standard validation pipeline
- Handler executes correctly through the grammar worker
- Capability schema derived from composition matches expected output

### Prototype 4: Capability Schema Generation

**Objective:** Generate capability schemas from handler compositions and validate they enable LLM planning.

**Success criteria:**

- Capability schemas derived automatically from composition specifications
- Claude can generate valid handler compositions when provided with capability schemas and grammar rules
- Generated compositions pass the validation pipeline including single-mutation boundary check
- Schemas include composition information (what primitives are involved, what error modes are possible)

### Prototype 5: FFI Surface

**Objective:** Validate that polyglot developers can use grammar handlers through FFI wrappers.

**Success criteria:**

- Python, Ruby, and TypeScript can invoke grammar primitives through FFI wrappers
- Serialization/deserialization across language boundary is correct
- Error propagation works (Rust errors become language-idiomatic exceptions)
- Performance overhead of FFI boundary is acceptable

---

## Validation Criteria for Phase Completion

1. Action grammar primitive framework implemented in Rust with compile-time data contracts
2. At least 7 primitives implemented (recommend: Acquire, Transform, Validate, Gate, Decide, FanOut, Aggregate) plus at least 2 mutating primitives (recommend: Persist, Emit)
3. Composition validation pipeline operational, enforcing contract compatibility, single-mutation boundary, and configuration validity
4. At least 5 common patterns documented and resolvable (recommend: http_request, transform, validate, gate, notify)
5. At least 3 dynamically-composed handlers demonstrated — including at least one non-linear (branching/multi-source) composition
6. Capability schemas derived automatically from composition specifications
7. A grammar worker deployment exists that validates and executes handler compositions
8. At least 3 example workflows authored using only grammar-composed handlers (no custom code)
9. FFI wrappers available for at least Python and TypeScript
10. Inter-step data flow works correctly with grammar-composed handlers in both static and conditional workflows
11. Documentation in `tasker-contrib` covering grammar primitives, handler composition, common patterns, and extension patterns

---

## Relationship to Other Phases

- **Phase 0** informs this phase: patterns from MCP server usage and TAS-280 code generation reveal which primitives and compositions are needed.
- **Phase 2** depends on this phase: the planning interface generates workflow fragments that reference grammar compositions.
- **Phase 3** uses this phase: recursive planning composes grammar primitives across multiple planning phases.
- **Agent integration** uses this phase: agents composing research workflows can assemble handler compositions for investigation steps directly from the grammar vocabulary.
- This phase is **independently valuable** regardless of whether subsequent phases are implemented.

---

*This document will be updated as Phase 0 progresses and reveals design insights, and as prototyping reveals which composition patterns work well in practice.*
