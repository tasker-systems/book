# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

This is the Tasker Documentation Hub - an mdBook-powered documentation site that aggregates content
from across the Tasker ecosystem. Content is synced from `tasker-core` and `tasker-contrib` sibling
repositories, then built into a static site deployed to GitHub Pages.

## Development Commands

### Quick Start

```bash
cargo make serve       # Sync + generate + build + serve locally (with hot reload)
cargo make build       # Sync + generate + build static site
cargo make sync        # Pull docs from sibling repos (without building)
cargo make generate    # Generate diagrams from source analysis
cargo make clean       # Remove build artifacts
```

### Pipeline Steps (individual)

```bash
cargo make sync        # Step 1: Sync from tasker-core/docs + tasker-contrib
cargo make generate    # Step 2: Generate diagrams from tasker-core source analysis
cargo make summary     # Step 3: Regenerate SUMMARY.md from directory structure
cargo make mdbook-build  # Step 4: Build mdBook (no sync)
cargo make mdbook-serve  # Step 4 alt: Serve with hot reload (no sync)
```

### Individual Generators (deterministic)

```bash
cargo make generate-crate-deps       # Crate dependency graph (Mermaid)
cargo make generate-state-machines   # State machine diagrams (Mermaid)
cargo make generate-db-schema        # Database ER diagram (Mermaid)
```

### LLM-Powered Generators (opt-in, use Ollama when available)

```bash
cargo make generate-adr-summary      # ADR summary table
cargo make generate-config-guide     # Configuration operational tuning guide
cargo make generate-error-guide      # Error troubleshooting guide
cargo make generate-all              # All generators including LLM-powered
```

### Full Refresh

```bash
cargo make refresh     # All steps: sync + generate + summary + build
```

### Markdown Linting

```bash
cargo make lint        # Check markdown formatting (no changes)
cargo make fix         # Auto-fix markdown formatting
cargo make setup-hooks # Install git pre-commit hook (lints staged .md files)
```

Configuration: `.markdownlint-cli2.jsonc` — uses `npx markdownlint-cli2` (no package.json needed).

## Architecture

### Content Flow

```
tasker-core/docs/ ──┐
                    ├──→ src/ ──┐
tasker-contrib/ ────┘           ├──→ mdbook build ──→ book/ ──→ GitHub Pages
tasker-core/src/  ──→ generate ─┘
  (Cargo.toml, .rs, .sql)
```

### Directory Structure

- **`src/`** - mdBook source directory (mix of hand-written and synced content)
  - `getting-started/` - Hand-written consumer guides
  - `stories/` - Hand-written blog series (being rewritten)
  - `architecture/`, `guides/`, `workers/`, etc. - Synced from tasker-core/docs
  - `generated/` - Generated reference docs (config, diagrams, schema from source analysis)
  - `contrib/` - Synced from tasker-contrib
- **`cargo-make/scripts/`** - Sync and generation scripts (sync-*.sh, generate-*.sh)
- **`archive/`** - Old GitBook-era blog posts (not published)
- **`theme/`** - Custom mdBook theme/CSS
- **`book/`** - Build output (gitignored)

### Content Sync

Sync scripts pull from sibling repos with selective exclusions:

- **Included from tasker-core/docs**: architecture, auth, benchmarks, decisions, generated, guides,
  observability, operations, principles, reference, security, testing, workers
- **Excluded**: ticket-specs (internal), development (contributor-focused), CLAUDE.md files
- **Included from tasker-contrib**: docs/README.md, examples/

### Content Refresh Workflow

1. Create a branch
2. Run `cargo make sync` (requires sibling repos present and up-to-date)
3. Run `cargo make generate` (generates diagrams from tasker-core source)
4. Run `cargo make summary` to regenerate SUMMARY.md
5. Run `mdbook serve` to verify locally
6. Commit, push, PR to main
7. Merge triggers GitHub Pages deploy

## Configuration

### Key Files

- **`book.toml`** - mdBook configuration and preprocessors
- **`Makefile.toml`** - cargo-make task definitions
- **`src/SUMMARY.md`** - Auto-generated table of contents
- **`.github/workflows/deploy.yml`** - CI/CD pipeline
- **`.markdownlint-cli2.jsonc`** - Markdown linting rules

### Environment Variables

- `TASKER_CORE_DIR` - Path to tasker-core (default: `../tasker-core`) — used by sync and generate scripts
- `TASKER_CONTRIB_DIR` - Path to tasker-contrib (default: `../tasker-contrib`)
- `OLLAMA_MODEL` - Ollama model for LLM-powered generators (default: `qwen2.5:14b`, configurable in `.env`)
- `SKIP_LLM` - Set to `true` to skip Ollama in LLM-powered generators

## Technology Stack

- **mdBook** - Static site generator (Rust ecosystem standard)
- **mdbook-mermaid** - Mermaid diagram rendering
- **cargo-make** - Task orchestration
- **GitHub Actions** - CI/CD to GitHub Pages

## Important Notes

- All published content is committed to this repo (CI just builds, no sync needed)
- SUMMARY.md is auto-generated - edit `cargo-make/scripts/generate-summary.sh` to change structure
- The `getting-started/` section has placeholder pages awaiting consumer documentation
- mdbook-admonish is temporarily disabled pending mdbook 0.5.x compatibility
