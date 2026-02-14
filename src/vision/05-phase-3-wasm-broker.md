# Phase 3: Sandboxed Execution via WASM Broker

*Security isolation and portable execution for catalog handlers*

---

## Phase Summary

The WASM broker provides a sandboxed execution environment for catalog handlers. It sits between the orchestration layer and handler execution, instantiating handler modules as WASM with controlled host function access. From the orchestration layer's perspective, the broker is a standard Tasker worker subscribing to a namespace queue. Internally, it provides isolation, resource control, and portability that native execution cannot.

This phase is architecturally independent of LLM planning — WASM sandboxing benefits all catalog handler execution. However, it becomes more important when handlers are configured by LLM planners, where the security boundary between "what the planner asked for" and "what actually executes" must be formally enforced.

---

## Research Areas

### 1. WASM Runtime Selection

**Question:** Which WASM runtime should host catalog handler execution?

**Research approach:**

- Evaluate Wasmtime (Bytecode Alliance), Wasmer, and WasmEdge against Tasker's requirements
- Assess WASI preview support, component model readiness, and host function APIs
- Benchmark cold start, sustained throughput, and memory overhead

**Evaluation criteria:**

| Criterion | Weight | Notes |
|-----------|--------|-------|
| Rust integration quality | High | Broker is Rust; native Rust bindings essential |
| WASI support maturity | High | Handlers need I/O through standardized interfaces |
| Host function flexibility | High | Custom host functions for HTTP, logging, I/O |
| Component model support | Medium | Future interop between handler modules |
| Cold start latency | Medium | Impacts per-step overhead |
| Memory isolation | High | Per-handler memory limits |
| Ecosystem and maintenance | Medium | Long-term viability |
| Async support | Medium | Handler I/O is inherently async |

**Current assessment (to be validated):**

- **Wasmtime**: Strongest Rust integration (same Bytecode Alliance as Cranelift). WASI Preview 2 support progressing. Component model being actively developed. Most likely choice.
- **Wasmer**: Good WASI support, additional features (WAPM registry), but different host function model. Evaluate if Wasmtime integration proves problematic.
- **WasmEdge**: Strong in edge/serverless context, lighter weight. Evaluate for resource-constrained deployments.

**Open questions:**

- Does Wasmtime's async host function support meet our needs for HTTP calls from within WASM modules?
- What is the practical memory overhead per WASM instance? (Determines concurrency model)
- Can we pre-compile (AOT) handler modules to eliminate cold start for known catalog handlers?

### 2. Host Function Interface Design

**Question:** What capabilities does the WASM sandbox expose to handlers, and through what interface?

**Research approach:**

- Enumerate all I/O operations catalog handlers need to perform
- Design a minimal, auditable host function surface
- Evaluate whether WASI standard interfaces cover our needs or require custom extensions

**Proposed host function surface:**

| Host Function | Purpose | Security Consideration |
|---------------|---------|----------------------|
| `http_request(url, method, headers, body) → response` | External API calls | URL allowlist, rate limiting, timeout enforcement |
| `log(level, message)` | Structured logging | Integrated with Tasker's telemetry pipeline |
| `read_input() → step_inputs` | Access step configuration and inputs | Read-only, scoped to current step |
| `write_output(result)` | Return handler result | Schema-validated before acceptance |
| `read_secret(key) → value` | Access secrets for auth | Scoped to declared secrets only, never persisted in logs |
| `get_time() → timestamp` | Current time for idempotency keys | Monotonic, controlled by host |

**Explicitly excluded:**

- Direct database access (all state management through orchestration layer)
- Filesystem access (handlers are stateless compute)
- Network access beyond HTTP (no raw sockets, no DNS resolution control)
- Inter-handler communication (all data flow through step results)
- Process spawning (no exec, no fork)

**Open questions:**

- Should `http_request` be a single function or decomposed (create_request, send, read_response) for streaming?
- How should the host handle handler timeouts? Kill the WASM instance? Cooperative cancellation?
- Should there be a `cache` host function for handlers that make repeated similar requests?
- How do we handle handlers that need to process large datasets? Streaming interface vs. chunked input?

### 3. Broker Architecture

**Question:** How does the WASM broker integrate with Tasker's worker infrastructure?

**Research approach:**

- Design the broker as a Tasker worker that subscribes to a dedicated namespace queue
- Evaluate concurrency models: one WASM instance per step? Instance pool? Pre-warmed instances?
- Determine how the broker maps step handler references to WASM modules

**Proposed architecture:**

```
┌─────────────────────────────────────────────────────┐
│                    WASM BROKER                       │
│                (Tasker Worker)                        │
├─────────────────────────────────────────────────────┤
│                                                      │
│  ┌──────────────┐    ┌─────────────────────────┐    │
│  │  Step Event   │───▶│  Module Registry         │    │
│  │  Receiver     │    │  ┌───────────────────┐  │    │
│  │  (PGMQ poll)  │    │  │ http_request.wasm │  │    │
│  └──────────────┘    │  │ transform.wasm    │  │    │
│         │            │  │ validate.wasm     │  │    │
│         ▼            │  │ ...               │  │    │
│  ┌──────────────┐    │  └───────────────────┘  │    │
│  │  Dispatch     │───▶│                         │    │
│  │  Service      │    └─────────────────────────┘    │
│  │  (semaphore-  │                                   │
│  │   bounded)    │    ┌─────────────────────────┐    │
│  └──────────────┘    │  WASM Runtime (Wasmtime)  │    │
│         │            │  ┌─────────────────────┐  │    │
│         ▼            │  │  Instance Pool       │  │    │
│  ┌──────────────┐    │  │  - Memory limits     │  │    │
│  │  Host Function│◀──│  │  - Execution timeout │  │    │
│  │  Provider     │    │  │  - I/O budgets      │  │    │
│  │  - HTTP       │    │  └─────────────────────┘  │    │
│  │  - Logging    │    └─────────────────────────┘    │
│  │  - I/O        │                                   │
│  │  - Secrets    │    ┌─────────────────────────┐    │
│  └──────────────┘    │  Result Reporter          │    │
│         │            │  (FFI complete_step_event) │    │
│         └───────────▶│                           │    │
│                      └─────────────────────────┘    │
│                                                      │
└─────────────────────────────────────────────────────┘
```

**Concurrency model options:**

| Model | Description | Trade-offs |
|-------|-------------|------------|
| **Instance-per-step** | New WASM instance for each step execution | Maximum isolation, cold start per step |
| **Pooled instances** | Pre-warmed pool, assign to steps | Amortized cold start, must ensure state cleanup between uses |
| **Dedicated instances** | One long-lived instance per handler type | Best throughput, weakest isolation between step executions |

**Recommendation:** Start with instance-per-step for maximum isolation and correctness. Optimize to pooled instances if cold start overhead is measurable (benchmark in Prototype 1).

**Open questions:**

- Should the broker support multiple catalog versions simultaneously? (Blue-green catalog deployments)
- How should the broker handle handler panics/traps? (WASM traps are well-defined; map to step failure with diagnostic)
- What metrics should the broker emit beyond standard step metrics? (WASM-specific: instantiation time, memory high-water mark, host function call counts)

### 4. Compilation and Distribution

**Question:** How are catalog handlers compiled to WASM and distributed to brokers?

**Research approach:**

- Establish a compilation pipeline from Rust handler source to `.wasm` modules
- Evaluate AOT (ahead-of-time) vs. JIT compilation strategies
- Design a module registry for versioned handler distribution

**Compilation pipeline:**

```
Rust handler source
    ↓ (cargo build --target wasm32-wasip1)
.wasm module
    ↓ (wasmtime compile → AOT)  [optional, for cold start optimization]
.cwasm pre-compiled module
    ↓ (publish to registry)
Module registry (filesystem, OCI, or custom)
    ↓ (broker startup or hot-refresh)
WASM Broker module cache
```

**Open questions:**

- Should catalog handler WASM modules be distributed as part of the broker container image or fetched at runtime?
- Can we compile catalog handlers written in languages other than Rust to WASM? (AssemblyScript for TypeScript handlers? wasm-pack for Rust?)
- What testing strategy validates that WASM-compiled handlers produce identical results to native execution?
- How do we handle handler configuration that references language-specific features? (WASM handlers should be language-agnostic)

### 5. Security Boundary Validation

**Question:** How do we verify that the WASM sandbox actually provides the security guarantees we claim?

**Research approach:**

- Define the threat model: what can a malicious handler configuration attempt?
- Design tests that verify sandbox containment
- Evaluate whether WASM isolation is sufficient or whether additional controls are needed

**Threat model for LLM-planned handlers:**

| Threat | Vector | Mitigation |
|--------|--------|------------|
| Data exfiltration | HTTP requests to attacker-controlled endpoints | URL allowlist on `http_request` host function |
| Resource exhaustion | Infinite loops, excessive memory allocation | Execution timeout, memory limits on WASM instance |
| Denial of service | Massive fan-out through planned steps | Resource bounds enforced at planning validation (Phase 2) |
| Secret extraction | Handler configuration designed to leak secrets through results | Secret values not included in step results; `read_secret` scoped and audited |
| Cross-step interference | Handler modifying state visible to other handlers | Instance-per-step isolation; no shared mutable state |
| Host function abuse | Excessive HTTP calls, log flooding | Rate limiting on host functions, log size caps |

---

## Prototyping Goals

### Prototype 1: WASM Handler Compilation and Execution

**Objective:** Compile a single catalog handler (recommend: `transform`) to WASM and execute it through a minimal broker.

**Success criteria:**

- Handler compiles to `wasm32-wasip1` target
- Broker instantiates the module, provides host functions, and receives results
- Results are identical to native Rust execution of the same handler with the same inputs
- Cold start and execution latency measured and documented

### Prototype 2: Host Function Surface

**Objective:** Implement the full host function interface and validate it supports all catalog handler requirements.

**Success criteria:**

- `http_request` host function makes external HTTP calls on behalf of WASM handlers
- URL allowlisting prevents unauthorized destinations
- Execution timeout kills runaway WASM instances cleanly
- Memory limits prevent excessive allocation

### Prototype 3: Broker as Tasker Worker

**Objective:** Integrate the WASM broker as a standard Tasker worker.

**Success criteria:**

- Broker subscribes to a namespace queue (e.g., `catalog_queue`)
- Steps routed to catalog handlers are executed through WASM
- Step results flow back through normal completion path
- Observable through standard Tasker telemetry

---

## Validation Criteria for Phase Completion

1. ✅ At least 3 catalog handlers compiled to WASM and executing correctly
2. ✅ WASM broker integrated as a Tasker worker processing steps from a namespace queue
3. ✅ Host function surface implemented with security controls (URL allowlist, timeouts, memory limits)
4. ✅ Performance benchmarks: cold start < 10ms, throughput within 2x of native execution
5. ✅ Security boundary validated against threat model (all identified threats mitigated)
6. ✅ Module registry supports versioned handler distribution
7. ✅ Broker telemetry includes WASM-specific metrics

---

## Relationship to Other Phases

- **Phase 1** is a prerequisite: catalog handlers are what gets compiled to WASM.
- **Phase 2** is enhanced by this phase: LLM-planned handlers execute with stronger isolation.
- **Phase 4** benefits from this phase: recursive planning with sandboxed execution provides defense in depth.
- This phase is **independently valuable**: WASM sandboxing benefits all catalog handler execution, not just LLM-planned workflows.

---

## Ecosystem Dependencies and Timing

This phase has the strongest dependency on external ecosystem maturity. Key milestones to monitor:

- **WASI Preview 2 stabilization**: Networking and async support needed for `http_request` host function
- **Wasmtime async host functions**: Required for non-blocking HTTP from within WASM
- **Component model maturity**: Future opportunity for handler composition at the WASM level

If WASI networking remains immature, a fallback architecture is available: the broker provides `http_request` as a host function implemented entirely in the Rust host (not delegated to WASM-internal networking). This is the recommended approach regardless, as it keeps the security boundary in the host.

---

*This document will be updated as WASM ecosystem maturity evolves and Phase 1 handler implementations inform compilation requirements.*
