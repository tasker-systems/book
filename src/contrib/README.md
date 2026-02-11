# Tasker Contrib Documentation

## Quick Links

| Document | Description |
|----------|-------------|
| [README.md](../README.md) | Repository overview, vision, and structure |
| [DEVELOPMENT.md](../DEVELOPMENT.md) | Local development and cross-repo setup |

## Implementation Specifications

| Ticket | Status | Description |
|--------|--------|-------------|
| [TAS-126](ticket-specs/TAS-126/) | 🚧 In Progress | Foundations: repo structure, vision, CLI plugin design |

### TAS-126 Documents

| Document | Description |
|----------|-------------|
| [README.md](ticket-specs/TAS-126/README.md) | Ticket summary and deliverables |
| [foundations.md](ticket-specs/TAS-126/foundations.md) | Architectural deep-dive and design rationale |
| [rails.md](ticket-specs/TAS-126/rails.md) | Rails-specific implementation plan |
| [cli-plugin-architecture.md](ticket-specs/TAS-126/cli-plugin-architecture.md) | CLI plugin system design |

## Architecture

The [foundations document](ticket-specs/TAS-126/foundations.md) covers:
- Design rationale (why separate repos, why Railtie over Engine)
- Framework integration patterns (lifecycle, events, generators)
- Configuration architecture (three-layer model)
- Testing architecture (unit, integration, E2E)
- Versioning strategy

## Milestones

| Milestone | Status | Description |
|-----------|--------|-------------|
| Foundations and CLI | 🚧 In Progress | TAS-126: Repo structure, vision, CLI plugin design |
| Rails | 📋 Planned | tasker-contrib-rails gem, generators, event bridge |
| Python | 📋 Planned | tasker-contrib-fastapi, pytest integration |
| TypeScript | 📋 Planned | tasker-contrib-bun, Bun.serve patterns |

## Framework Guides

*Coming soon as packages are implemented*

- Rails Integration Guide
- FastAPI Integration Guide
- Bun Integration Guide
- Axum Integration Guide

## Operational Guides

*Coming soon*

- Helm Chart Deployment
- Terraform Infrastructure
- Monitoring Setup
- Production Checklist
