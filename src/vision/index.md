# Generative Workflows, Deterministic Execution

**Status:** Vision & Planning
**Created:** 2026-02-14
**Revised:** 2026-02-22
**Author:** Pete (with Claude collaboration)

---

## Overview

This document set describes a vision for extending Tasker Core's workflow orchestration capabilities toward *generative workflows* — workflows whose components can be progressively generated from increasingly abstract descriptions, while preserving the deterministic execution guarantees that make Tasker trustworthy.

The core insight: Tasker's execution properties (idempotency, transactional step creation, state machine consistency, DAG-ordered dependencies) create a foundation strong enough to support non-deterministic planning. An LLM or developer tool reasons about *what* should happen; the system guarantees *how* it executes.

The path from here to there is incremental. Each phase delivers independent value — better developer tooling, composable handler primitives, LLM-assisted authoring — while building toward a system where an LLM can generate validated workflow segments from runtime context, composed from Rust-enforced action grammar primitives.

## Documents

| Document | Purpose |
|----------|---------|
| [01 - Vision](01-vision.md) | The philosophical and architectural "why" — how deterministic execution enables generative workflows, the action grammar concept, and the two-tier trust model |
| [02 - Technical Approach](02-technical-approach.md) | Problem statement, solution space analysis, recommendation, and phase overview |
| [03 - Phase 0: Foundation](03-phase-0-foundation.md) | Templates as generative contracts — TAS-280, MCP server, and the groundwork for everything that follows |
| [04 - Phase 1: Action Grammars](04-phase-1-action-grammars.md) | Rust-native composable action primitives and the handler catalog built from them |
| [05 - Phase 2: Planning Interface](05-phase-2-planning-interface.md) | LLM-backed planning steps and workflow fragment generation |
| [06 - Phase 3: Recursive Planning](06-phase-3-recursive-planning.md) | Multi-phase adaptive workflows with accumulated context |
| [07 - Complexity Management](07-complexity-management.md) | Observability, operator experience, LLM context management, and avoiding complication |

## Reading Order

For understanding the vision: start with **01**, then **07** for the complexity framing.

For the pragmatic path: **03** (Phase 0) describes the immediately actionable work that establishes the foundation.

For technical depth: **02** gives the full analysis, then dive into whichever phase is most relevant.

For implementation: **03** (Phase 0) is the starting point — it delivers independent value and informs every subsequent phase.

## Key Principles

- **The step remains the atom.** Dynamic planning introduces new topology, not new mechanics.
- **Action grammars are the vocabulary.** Composable, Rust-enforced primitives that an LLM can compose without breaking.
- **Data contracts are the glue.** Compile-time enforced input/output shapes make composition provably correct.
- **Two trust tiers.** Developer-authored handlers are the developer's responsibility. System-invoked action grammars are the system's responsibility, with the strongest guarantees the language can provide.
- **Validation is the trust boundary.** Every workflow fragment is validated before execution.
- **The template is the safety contract.** Planning fills in the middle; the frame is fixed.
- **Each phase is independently valuable.** TAS-280 improves developer experience. The handler catalog improves workflow authoring. Neither requires LLM integration to justify its existence.

## Relationship to Existing Work

This initiative builds directly on:

- **TAS-280**: Typed handler generation from task templates — the first step toward templates as generative contracts
- **TAS-294**: Functional DSL for handler registration — the developer-facing composition pattern
- **TAS-53**: Dynamic workflow decision points (conditional workflows) — the execution foundation
- **TAS-112**: Cross-language ergonomics analysis (handler patterns)
- **Intentional AI Partnership**: The philosophical foundation for human-AI collaboration in the system

**Related but independent:** WASM-based handler sandboxing (explored in prior vision work) is a valuable capability for execution isolation and portability, but is orthogonal to this initiative. It can be pursued as a parallel effort and would complement the handler catalog regardless of LLM integration.

---

*These documents describe a vision. Implementation will be tracked through Linear tickets as each phase progresses from research to prototyping to delivery.*
