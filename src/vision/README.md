# Dynamic Workflow Planning Initiative

*Probabilistic Planning, Deterministic Execution*

**Status:** Vision & Planning  
**Created:** 2026-02-14  
**Author:** Pete (with Claude collaboration)

---

## Overview

This document set describes a vision for extending Tasker Core's conditional workflow capabilities to support LLM-backed workflow planning. The core insight: Tasker's deterministic execution guarantees (idempotency, transactional step creation, state machine consistency) create space for non-deterministic planning. An LLM reasons about *what* should happen; the system guarantees *how* it executes.

## Documents

| Document | Purpose |
|----------|---------|
| [01 - Vision](01-vision.md) | The philosophical and architectural "why" — how deterministic execution enables probabilistic planning, building from existing Tasker affordances |
| [02 - Technical Approach](02-technical-approach.md) | Problem statement, solution space analysis, recommendation, and phase overview |
| [03 - Phase 1: Handler Catalog](03-phase-1-handler-catalog.md) | Generic composable step handlers as the vocabulary of dynamic planning |
| [04 - Phase 2: Planning Interface](04-phase-2-planning-interface.md) | LLM-backed planning steps and workflow fragment generation |
| [05 - Phase 3: WASM Broker](05-phase-3-wasm-broker.md) | Sandboxed execution for catalog handlers |
| [06 - Phase 4: Recursive Planning](06-phase-4-recursive-planning.md) | Multi-phase adaptive workflows with accumulated context |
| [07 - Complexity Management](07-complexity-management.md) | Observability, operator experience, LLM context management, and avoiding complication |

## Reading Order

For understanding the vision: start with **01**, then **07** for the complexity framing.

For technical planning: **02** gives the full picture, then dive into whichever phase is most relevant.

For implementation: **03** (Phase 1) is the starting point regardless — it delivers independent value and is the foundation for everything that follows.

## Key Principles

- **The step remains the atom.** Dynamic planning introduces new topology, not new mechanics.
- **Validation is the trust boundary.** Every workflow fragment is validated before execution.
- **The template is the safety contract.** Planning fills in the middle; the frame is fixed.
- **Provenance is metadata, not structure.** Planned steps are steps, with additional context.
- **Each phase is independently valuable.** The handler catalog improves Tasker even without LLM integration.

## Relationship to Existing Work

This initiative builds directly on:

- **TAS-53**: Dynamic workflow decision points (conditional workflows)
- **TAS-112**: Cross-language ergonomics analysis (handler patterns)
- **TAS-100**: FFI vs. WASM analysis (informs Phase 3)
- **TAS-150+**: Serverless WASM handlers vision (aligned with Phase 3)
- **Intentional AI Partnership**: The philosophical foundation for human-AI collaboration in the system

---

*These documents describe a vision. Implementation will be tracked through Linear tickets as each phase progresses from research to prototyping to delivery.*
