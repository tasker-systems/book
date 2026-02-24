# Generative Workflows, Deterministic Execution

**Status:** Vision & Planning
**Created:** 2026-02-14
**Revised:** 2026-02-23
**Author:** Pete (with Claude collaboration)

---

## Overview

This document set describes a vision for extending Tasker Core's workflow orchestration capabilities toward *generative workflows* — workflows whose components can be progressively generated from increasingly abstract descriptions, while preserving the deterministic execution guarantees that make Tasker trustworthy.

The core insight: Tasker's execution properties (idempotency, transactional step creation, state machine consistency, DAG-ordered dependencies) create a foundation strong enough to support non-deterministic planning. An LLM or developer tool reasons about *what* should happen; the system guarantees *how* it executes. These same properties make Tasker valuable infrastructure for autonomous agents — not as an agent framework, but as deterministic execution infrastructure that agents use as clients.

The path from here to there is incremental. Each phase delivers independent value — better developer tooling, composable handler primitives, LLM-assisted authoring, agent-accessible infrastructure — while building toward a system where any client (human, LLM, or agent) can compose validated workflow segments from Rust-enforced action grammar primitives.

## Documents

| Document | Purpose |
|----------|---------|
| [01 - Vision](01-vision.md) | The philosophical and architectural "why" — how deterministic execution enables generative workflows, the action grammar concept, agent integration, and the two-tier trust model |
| [02 - Technical Approach](02-technical-approach.md) | Problem statement, solution space analysis (including agent-accessible infrastructure), recommendation, and phase overview |
| [03 - Phase 0: Foundation](03-phase-0-foundation.md) | Templates as generative contracts — TAS-280, MCP server, shared tooling crate, and the groundwork for everything that follows |
| [04 - Phase 1: Action Grammars](04-phase-1-action-grammars.md) | Rust-native composable action primitives, common patterns, and the unified composition model |
| [05 - Agent Orchestration](05-agent-orchestration.md) | How agents use Tasker as deterministic infrastructure — context decomposition, research workflows, and the shared tooling foundation |
| [06 - Phase 2: Planning Interface](06-phase-2-planning-interface.md) | LLM-backed planning steps and workflow fragment generation from grammar compositions |
| [07 - Phase 3: Recursive Planning](07-phase-3-recursive-planning.md) | Multi-phase adaptive workflows — step-level recursion and task-level delegation |
| [08 - Complexity Management](08-complexity-management.md) | Observability, operator experience, LLM context management, agent lineage, and avoiding complication |

## Reading Order

For understanding the vision: start with **01**, then **08** for the complexity framing.

For the agent story: **01** introduces the concept, **05** gives the full treatment.

For the pragmatic path: **03** (Phase 0) describes the immediately actionable work that establishes the foundation.

For technical depth: **02** gives the full analysis, then dive into whichever phase is most relevant.

For implementation: **03** (Phase 0) is the starting point — it delivers independent value and informs every subsequent phase.

## Key Principles

- **The step remains the atom.** Dynamic planning introduces new topology, not new mechanics.
- **Action grammars are the vocabulary.** Composable, Rust-enforced primitives that any client can compose without breaking.
- **One composition model.** All handler composition uses the same `action(resource)` grammar. Common patterns are named, well-tested composition specifications. Dynamic compositions use the same grammar and validation pipeline.
- **The single-mutation boundary is the safety invariant.** A valid composition has at most one external mutation (Persist, Emit), and it appears after all fallible preparatory work. Primitives are compile-time verified Rust; compositions are validated at assembly time against structural invariants.
- **Two trust tiers.** Developer-authored handlers are the developer's responsibility. System-invoked action grammars are the system's responsibility, with the strongest guarantees the language can provide.
- **Agents are clients, not components.** Tasker provides deterministic infrastructure; agents provide reasoning. The API is the same regardless of who submits the task.
- **Validation is the trust boundary.** Every workflow fragment is validated before execution.
- **The template is the safety contract.** Planning fills in the middle; the frame is fixed.
- **Each phase is independently valuable.** TAS-280 improves developer experience. Grammar-composed handlers improve workflow authoring. Agent integration is a cross-cutting capability that enriches each phase.

## Relationship to Existing Work

This initiative builds directly on:

- **TAS-280**: Typed handler generation from task templates — the first step toward templates as generative contracts
- **TAS-294**: Functional DSL for handler registration — the developer-facing composition pattern
- **TAS-53**: Dynamic workflow decision points (conditional workflows) — the execution foundation
- **TAS-112**: Cross-language ergonomics analysis (handler patterns)
- **Intentional AI Partnership**: The philosophical foundation for human-AI collaboration in the system

---

*These documents describe a vision. Implementation will be tracked through Linear tickets as each phase progresses from research to prototyping to delivery.*
