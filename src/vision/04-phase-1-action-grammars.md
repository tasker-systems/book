# Phase 1: Action Grammars and Handler Catalog

*Rust-native composable action primitives as the vocabulary of generative workflow planning*

---

## Phase Summary

The action grammar is a framework of composable, Rust-native primitives with compile-time enforced data contracts. Each primitive performs a single, well-defined action — acquiring data, transforming shapes, validating invariants, gating on conditions — with declared input and output types that the Rust compiler verifies at composition time. The handler catalog is the composed layer: pre-built handlers assembled from grammar primitives, each representing a business-meaningful operation (HTTP request with auth and error handling, schema-validated data transformation, approval-gated checkpoint).

This phase delivers independent value. Even without LLM integration, composable handlers reduce the boilerplate of workflow authoring, provide stronger correctness guarantees than hand-written handlers, and enable a richer template ecosystem in `tasker-contrib`. The action grammar layer also provides the vocabulary that Phase 2's LLM planner composes from — a vocabulary the planner cannot break because the type system prevents invalid compositions.

---

## Research Areas

### 1. Action Grammar Primitives

**Question:** What are the fundamental verbs of workflow action, and how do they differ from handlers?

**The distinction:** A primitive has a single concern with compile-time enforced input/output contracts. A handler composes primitives into a business-meaningful action. The primitive is the atom; the handler is the molecule.

**Research approach:**

- Audit existing Tasker example workflows and extract recurring low-level actions
- Analyze Phase 0 MCP server usage patterns to identify what compositions developers actually request
- Survey workflow primitives in competing systems (Airflow operators, Temporal activities, Prefect tasks, Step Functions integrations) at a lower granularity than their handler-level abstractions
- Categorize by action type: I/O, computation, control flow, aggregation

**Proposed primitive taxonomy:**

| Primitive | Concern | Input Contract | Output Contract |
|-----------|---------|---------------|----------------|
| `Acquire` | Fetch data from an external source | Source descriptor (URL, query, config) | Raw acquired data + metadata (status, timing) |
| `Transform` | Reshape data from one form to another | Input data + transformation spec | Transformed data conforming to target shape |
| `Validate` | Assert invariants on data | Data + validation rules | Partitioned results (valid set, invalid set, diagnostics) |
| `Gate` | Block execution pending a condition | Gate condition + notification config | Approval/rejection + gating metadata |
| `Emit` | Send data to an external destination | Data + destination descriptor | Delivery confirmation + metadata |
| `Decide` | Evaluate conditions and select a path | Decision context + routing rules | Selected path identifier + reasoning |
| `FanOut` | Decompose work into parallel units | Data source + partitioning strategy | Partition descriptors for parallel execution |
| `Aggregate` | Converge and reduce parallel results | Collection of results + reduction strategy | Reduced result conforming to output shape |

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
- Design the `dyn Pluggable` boundary for plugin extensibility

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

**The plugin boundary:**

Not all compositions can be statically known. Organization-specific primitives, user-defined transformations, and integration-specific adapters need a dynamic extension point. This is where `dyn Pluggable` comes in — a trait object boundary that allows runtime dispatch while still requiring the data contracts to be declared:

```rust
/// Plugin primitives declare their contracts but dispatch dynamically
trait PluggablePrimitive: Send + Sync {
    fn input_schema(&self) -> &JsonSchema;
    fn output_schema(&self) -> &JsonSchema;
    fn execute(&self, input: serde_json::Value) -> Result<serde_json::Value, ActionError>;
}
```

At the plugin boundary, contracts are validated at registration time (JSON Schema matching) rather than compile time. This is weaker than static composition but still stronger than no validation — the system rejects incompatible plugins at startup, not at step execution time.

**Open questions:**

- How do we handle optional fields in data contracts? (A transform that adds fields to its input — the output is a superset of the input type.)
- Should compositions be linear (A → B → C) or support branching (A → B + C → D)?
- How do we express that a primitive preserves certain fields while transforming others? (Partial type transformations are hard to express statically.)
- What is the right balance between static composition (maximum safety, less flexibility) and dynamic dispatch (more flexibility, weaker guarantees)?

### 3. Composition Rules

**Question:** How do primitives combine into handlers while preserving idempotency, single responsibility, and retryability?

**Research approach:**

- Define which compositions are valid from an execution-guarantee perspective (not just type compatibility)
- Design the mixin/layering approach for building handlers from primitives
- Validate that composed handlers maintain the step contract (idempotent, retryable, side-effect bounded)

**Composition properties that must be preserved:**

| Property | Primitive Requirement | Composition Rule |
|----------|----------------------|------------------|
| **Idempotency** | Each primitive must be idempotent with respect to its side effects | A composition is idempotent if all its primitives are idempotent. Side-effecting primitives (Acquire, Emit) must declare their idempotency strategy (idempotency keys, conditional execution). |
| **Retryability** | Each primitive must be safe to re-execute | A composition is retryable if re-execution from the beginning is safe. Primitives with external side effects must handle duplicate suppression. |
| **Single responsibility** | Each primitive has one concern | A composition's "single responsibility" is the business action it represents. The primitives within are the decomposed steps of that action. |
| **Side-effect boundary** | Side effects are explicit and bounded | A composition's side-effect boundary is the union of its primitives' side effects. The composition must declare this. |

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

### 4. Handler Catalog

**Question:** What does the catalog look like as a library of composed handlers, and how are capability schemas derived?

**Research approach:**

- Design the catalog as a registry of named compositions with metadata
- Derive capability schemas from grammar composition types rather than hand-authoring them
- Validate that derived schemas are sufficient for LLM planning (Phase 2)

**Catalog structure:**

Each catalog entry is a named, parameterized composition:

```yaml
name: http_request
description: >
  Makes an HTTP request to an external service with configurable authentication,
  error handling, and response extraction. Built from Acquire + Transform + Validate
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

**Capability schema derivation:**

Because catalog handlers are compositions of typed primitives, their capability schemas can be *derived* from the composition rather than hand-authored. The input contract is the first primitive's input type, parameterized by the handler's configuration. The output contract is the last primitive's output type. The error modes are the union of each primitive's error types. This derivation is mechanistic and always accurate — the capability schema cannot drift from the implementation because it is generated from the same type definitions.

**Proposed initial catalog:**

| Handler | Composition | Key Parameters |
|---------|-------------|----------------|
| `http_request` | Acquire(Http) → Transform(Extract) → Validate(Status) | URL, method, headers, body, auth, extraction path |
| `transform` | Transform(Reshape) | Input mapping, output schema, transformation rules |
| `validate` | Validate(Schema) | JSON Schema, error strategy (fail/flag/filter) |
| `fan_out` | FanOut(Partition) | Data source, partition strategy, max concurrency |
| `aggregate` | Aggregate(Reduce) | Reduction strategy, failure threshold, output schema |
| `gate` | Gate(Approval) → Emit(Notification) | Notification config, approval criteria, timeout |
| `notify` | Emit(Channel) | Channel type (webhook/email/slack), template, recipients |
| `decide` | Decide(Rules) | Decision logic config, possible outcomes, routing rules |

**Open questions:**

- Should the catalog support versioned handlers? (Upgrading a composition without breaking existing templates.)
- How should organization-specific catalog entries be registered alongside standard ones?
- Should there be a `compose` CLI command in `tasker-ctl` that helps developers build custom catalog entries from primitives?

### 5. FFI Surface for Polyglot Consumption

**Question:** How do Python, Ruby, and TypeScript developers use Rust-implemented action grammars?

**Research approach:**

- Design the boundary between Rust grammar layer and polyglot developer layer
- Evaluate whether polyglot developers interact with grammar primitives directly or only through composed catalog handlers
- Prototype FFI bindings for catalog handler invocation

**Design principle:** Polyglot developers should not need to understand Rust. They interact with action grammars through two paths:

**Path 1: Configuration-driven catalog usage.** A developer references a catalog handler in their task template YAML. The handler executes in the Rust catalog worker. No language-specific code needed:

```yaml
steps:
  - name: fetch_records
    handler:
      catalog: http_request
      config:
        url: "https://api.example.com/records"
        method: GET
        response_extract: "$.data"
```

**Path 2: Language-specific DSL wrappers.** For developers who want to compose catalog handlers with their own business logic in the same step, thin FFI wrappers expose catalog primitives through each language's DSL:

```python
@step_handler("enrich_and_validate")
@depends_on(records="fetch_records")
def enrich_and_validate(records, context):
    # Use catalog primitive through FFI wrapper
    validated = context.catalog.validate(records, schema="record_v2")
    enriched = context.catalog.http_request(
        url="https://enrichment.example.com/v2/enrich",
        method="POST",
        body={"records": validated.valid_records}
    )
    return {"enriched": enriched, "invalid": validated.invalid_records}
```

The FFI wrapper handles serialization/deserialization across the language boundary. The Rust grammar layer executes the primitive with full type checking. The developer gets the safety of the grammar without leaving their language.

**Open questions:**

- Should FFI wrappers expose individual primitives or only composed catalog handlers?
- What is the serialization overhead of crossing the FFI boundary for each primitive call? (May need batching or composition-level FFI rather than primitive-level.)
- How should errors from Rust grammar execution be translated to language-idiomatic exceptions?
- Should there be a "local catalog worker" mode where catalog handlers execute in-process rather than through queue dispatch?

---

## Prototyping Goals

### Prototype 1: Primitive Framework and Basic Compositions

**Objective:** Implement the `ActionPrimitive` trait system, `Acquire`, `Transform`, and `Validate` primitives, and demonstrate composition with compile-time type checking.

**Success criteria:**

- Primitive trait with associated Input/Output types compiles and works
- Valid compositions compile; invalid compositions (type mismatch) fail to compile with clear error messages
- A simple composition (Acquire → Transform → Validate) executes correctly with test data
- Mixin wrappers (WithRetry, WithObservability) compose with core primitives

### Prototype 2: Catalog Handler from Composition

**Objective:** Build the `http_request` catalog handler as a composition of primitives and execute it through a catalog worker.

**Success criteria:**

- `http_request` handler assembled from Acquire(Http) → Transform(Extract) → Validate(Status)
- Handler executes correctly with parameterized configuration
- Error handling (timeouts, validation failures, unexpected responses) works as configured
- Handler is registered in a catalog worker that subscribes to a dedicated namespace
- Capability schema derived from composition types matches expected output

### Prototype 3: Capability Schema Generation

**Objective:** Generate capability schemas from handler compositions and validate they enable LLM planning.

**Success criteria:**

- Capability schemas derived automatically from composition types
- Claude can generate valid handler configurations when provided with capability schemas
- Generated configurations pass schema validation
- Schemas include composition information (what primitives are involved, what error modes are possible)

### Prototype 4: FFI Surface

**Objective:** Validate that polyglot developers can use catalog handlers through FFI wrappers.

**Success criteria:**

- Python, Ruby, and TypeScript can invoke catalog primitives through FFI wrappers
- Serialization/deserialization across language boundary is correct
- Error propagation works (Rust errors become language-idiomatic exceptions)
- Performance overhead of FFI boundary is acceptable

---

## Validation Criteria for Phase Completion

1. Action grammar primitive framework implemented in Rust with compile-time data contracts
2. At least 5 primitives implemented (recommend: Acquire, Transform, Validate, Gate, Emit)
3. At least 5 catalog handlers composed from primitives (recommend: http_request, transform, validate, gate, notify)
4. Capability schemas derived from composition types for all catalog handlers
5. A catalog worker deployment exists that registers all standard handlers
6. At least 3 example workflows authored using only catalog handlers (no custom code)
7. FFI wrappers available for at least Python and TypeScript
8. Inter-step data flow works correctly with catalog handlers in both static and conditional workflows
9. Documentation in `tasker-contrib` covering handler usage, grammar composition, and extension patterns

---

## Relationship to Other Phases

- **Phase 0** informs this phase: patterns from MCP server usage and TAS-280 code generation reveal which primitives and compositions are needed.
- **Phase 2** depends on this phase: the planning interface generates workflow fragments that reference grammar compositions.
- **Phase 3** uses this phase: recursive planning composes grammar primitives across multiple planning phases.
- This phase is **independently valuable** regardless of whether subsequent phases are implemented.

---

*This document will be updated as Phase 0 progresses and reveals design insights, and as prototyping reveals which composition patterns work well in practice.*
