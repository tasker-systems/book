# Phase 0: Foundation — Templates as Generative Contracts

*Developer tooling that delivers immediate value while building toward generative workflow capabilities*

---

## Phase Summary

Phase 0 establishes the foundation for generative workflows by extending Tasker's existing tooling in two directions: **typed code generation from task templates** (TAS-280) and an **MCP server for LLM-assisted workflow authoring**. Neither capability requires changes to Tasker's orchestration runtime. Both deliver immediate developer experience improvements. Together, they transform the TaskTemplate from a structural description into a generative contract — a machine-readable specification from which code, tests, validation, and eventually workflow fragments can be produced.

This phase is where we learn what patterns developers actually need, what the LLM gets right and wrong when generating workflow components, and what data contracts look like in practice. These lessons directly inform the design of action grammars in Phase 1.

---

## Research Areas

### 1. Result Schemas and Typed Code Generation (TAS-280)

**Question:** How do we make the TaskTemplate a source of typed, validated code generation?

**Context:** TAS-280 introduces an optional `result_schema` on step definitions — a JSON Schema describing what each step produces. The orchestrator stores whatever JSON the handler returns; the schema is metadata for tooling, not runtime enforcement. From this schema, `tasker-ctl generate` produces typed handler scaffolds, result models, and test scaffolds in all four supported languages.

**What this establishes for the vision:**

The `result_schema` is the first instance of a *data contract* in Tasker. It declares the shape of what flows between steps. Today, this contract is advisory — it drives code generation and developer experience. In Phase 1, these same data contracts become the compile-time enforced input/output specifications for action grammar primitives.

```yaml
steps:
  - name: validate_order
    handler:
      callable: handlers.validate_order
    result_schema:
      type: object
      required: [validated, order_total, item_count]
      properties:
        validated: { type: boolean }
        order_total: { type: number }
        item_count: { type: integer }

  - name: charge_payment
    dependencies: [validate_order]
    handler:
      callable: handlers.charge_payment
    result_schema:
      type: object
      required: [charge_id, amount_charged]
      properties:
        charge_id: { type: string }
        amount_charged: { type: number }
```

From this, `tasker-ctl` generates typed handler code where dependency results are deserialized into language-specific models — Pydantic `BaseModel` in Python, `Dry::Struct` in Ruby, TypeScript interfaces, Rust `#[derive(Deserialize)]` structs. The handler author gets IDE autocomplete, type checking, and compile-time or lint-time guarantees that their code matches the workflow's data flow.

**Research questions:**

- What is the minimal `result_schema` that produces useful typed code? (Full JSON Schema is expressive but verbose; a constrained subset may be more practical.)
- How should schema evolution work? When a step's output shape changes, what tooling helps propagate that change to downstream handlers?
- Should `tasker-ctl` validate schema compatibility between connected steps? (Step A produces shape X; step B declares it depends on A — does B's expected input match A's declared output?)
- What patterns emerge from real-world schema usage that inform action grammar data contract design?

### 2. MCP Server for Template and Handler Authoring

**Question:** How can an LLM assist developers in creating correct, well-structured workflows within Tasker's existing framework?

**Research approach:**

An MCP server exposes Tasker's template structure, handler patterns, and validation rules as tools that an LLM can use during a developer's authoring session. The developer describes what they're building; the LLM generates templates, handler code, and tests using Tasker's actual patterns and conventions.

**Proposed MCP server capabilities:**

| Capability | Description |
|-----------|-------------|
| **Template generation** | Given a natural language description of a workflow, generate a well-structured TaskTemplate YAML with step definitions, dependencies, and handler references |
| **Handler scaffolding** | Given a template and step name, generate handler code in the developer's chosen language using the DSL patterns from the appropriate framework integration |
| **Test scaffolding** | Generate test code that exercises the handler with realistic inputs and asserts expected output shapes |
| **Template validation** | Check a developer-authored template for structural correctness — valid step references, acyclic dependencies, handler callable format matching language conventions |
| **Handler resolution check** | Verify that handler callables in a template match registered handler names in the codebase, catching registration mismatches before runtime |
| **Request generation** | From a template's `input_schema`, generate example `curl` commands, `tasker-ctl` invocations, or language-specific `TaskerClient` calls for submitting task requests |

**What this establishes for the vision:**

The MCP server is a prototype of the LLM integration pattern that Phase 2 formalizes. The MCP server helps an LLM generate *developer-space* workflow components (templates, handlers, tests) from descriptions. Phase 2's planning interface helps an LLM generate *system-space* workflow fragments (steps, configurations, dependencies) from runtime context. The lessons from MCP server development — prompt engineering, structured output quality, validation feedback loops — transfer directly to planning step design.

The MCP server also creates a natural feedback loop: as developers use LLM-assisted authoring, we observe which patterns the LLM recommends, which mistakes it makes, and which workflow shapes recur across use cases. These observations inform the action grammar design — the recurring patterns become candidates for grammar primitives.

**Research questions:**

- What prompt patterns produce the best template quality? (Few-shot examples from `tasker-contrib`? Schema-constrained output? Iterative refinement with validation feedback?)
- How much of the TaskTemplate JSON Schema does the LLM need in its context to generate valid templates?
- What is the right boundary between MCP server validation and `tasker-ctl` validation? (The MCP server should catch obvious errors during authoring; `tasker-ctl` provides definitive validation.)
- Should the MCP server be aware of the codebase's existing handlers, or generate templates against the catalog of *possible* handlers?

### 3. TaskTemplate as Generative Input

**Question:** What makes the TaskTemplate a suitable foundation for progressive levels of code generation?

**Context:** The TaskTemplate already serves multiple roles:

- **Structural description** — defines steps, dependencies, and handler references
- **Input validation** — `input_schema` (JSON Schema) validates task request payloads
- **Configuration carrier** — `step_inputs` parameterize handler behavior
- **Queue routing** — `namespace_name` determines which workers process the task's steps

With `result_schema` (TAS-280), the template gains a fourth dimension: **output contracts** that describe what flows between steps. This makes the template a complete description of a workflow's data flow — what goes in, what each step produces, how data moves between steps, and what comes out.

**The generative progression:**

| Level | Input | Output | Phase |
|-------|-------|--------|-------|
| **Type generation** | Template + `result_schema` | Typed models, handler scaffolds, tests | Phase 0 (TAS-280) |
| **Authoring assistance** | Natural language description | Complete template + handler code + tests | Phase 0 (MCP server) |
| **Action grammar composition** | Template + catalog schema | Composed handlers from grammar primitives | Phase 1 |
| **Workflow fragment generation** | Runtime context + capability schema | Validated workflow fragments | Phase 2 |
| **Adaptive planning** | Accumulated results + capability schema | Multi-phase workflow plans | Phase 3 |

Each level builds on the previous. The template's structure, schemas, and data contracts are the common thread — the machine-readable specification that each level of generation reads from and produces into.

**Research questions:**

- Does the current TaskTemplate schema need extension to support generative use cases, or is `result_schema` sufficient for Phase 0?
- Should template metadata include hints for generation (e.g., "this step typically handles authentication," "this step is a good candidate for batching")?
- How should the relationship between `input_schema`, `result_schema`, and `step_inputs` be documented for LLM consumption?

---

## Prototyping Goals

### Prototype 1: Typed Code Generation (TAS-280)

**Objective:** Deliver `tasker-ctl generate` with typed handler scaffolding from `result_schema`.

**Success criteria:**

- `result_schema` parsed in TaskTemplate step definitions
- `tasker-ctl generate types` produces language-specific models (Python Pydantic, Ruby Dry::Struct, TypeScript interface, Rust struct) from schemas
- `tasker-ctl generate handler` produces DSL handler scaffolds with typed dependency injection
- Generated code compiles/type-checks in all four languages
- Test scaffolds reference expected output shapes

### Prototype 2: MCP Server — Template Validation

**Objective:** An MCP server that validates existing templates and checks handler resolution.

**Success criteria:**

- MCP server exposes template validation as a tool
- Structural validation catches dependency cycles, missing handler references, invalid step configurations
- Handler resolution checking validates callable strings against codebase patterns
- Validation feedback is actionable by both developers and LLMs

### Prototype 3: MCP Server — Template Generation

**Objective:** An MCP server that generates templates and handler code from natural language descriptions.

**Success criteria:**

- Given a workflow description, the MCP server generates a structurally valid TaskTemplate
- Generated templates pass the validation from Prototype 2
- Generated handler code uses the correct DSL patterns for the target language
- The LLM produces valid templates > 80% of the time without human correction

---

## Validation Criteria for Phase Completion

1. `result_schema` supported in TaskTemplate step definitions with typed code generation in all four languages
2. MCP server operational with template validation and handler resolution checking
3. MCP server generates structurally valid templates from natural language descriptions
4. At least 3 end-to-end examples: description → template → generated handlers → passing tests
5. Documented patterns from MCP server usage that inform action grammar design (recurring workflow shapes, common handler compositions, typical data flow patterns)
6. Schema compatibility checking between connected steps (step A's output matches step B's expected input)

---

## Relationship to Other Phases

- **Phase 1** is informed by this phase: patterns observed through MCP server usage and code generation reveal which action grammar primitives are needed and what data contracts look like in practice.
- **Phase 2** builds on this phase: the MCP server's LLM integration patterns (prompt engineering, validation feedback, structured output) transfer directly to planning step design.
- **Phase 3** is independent of this phase but benefits from the data contract foundation established here.
- This phase is **independently valuable** regardless of whether subsequent phases are implemented. TAS-280 and the MCP server improve developer experience for all Tasker users.

---

*This phase is the most immediately actionable. TAS-280 is already specified and ready for implementation. The MCP server can begin prototyping as soon as TAS-280 establishes the template extension patterns.*
