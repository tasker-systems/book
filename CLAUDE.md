# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Project Overview

This is the Tasker Documentation Hub - an mdBook-powered documentation site that aggregates content from across the Tasker ecosystem. Content is synced from `tasker-core` and `tasker-contrib` sibling repositories, then built into a static site deployed to GitHub Pages.

## Development Commands

### Quick Start
```bash
cargo make serve       # Sync content + build + serve locally (with hot reload)
cargo make build       # Sync content + build static site
cargo make sync        # Pull docs from sibling repos (without building)
cargo make clean       # Remove build artifacts
```

### Pipeline Steps (individual)
```bash
cargo make sync        # Step 1: Sync from tasker-core/docs + tasker-contrib
cargo make summary     # Step 2: Regenerate SUMMARY.md from directory structure
cargo make mdbook-build  # Step 3: Build mdBook (no sync)
cargo make mdbook-serve  # Step 3 alt: Serve with hot reload (no sync)
```

### Full Refresh
```bash
cargo make refresh     # All steps: sync + summary + build
```

## Architecture

### Content Flow
```
tasker-core/docs/ ──┐
                    ├──→ src/ ──→ mdbook build ──→ book/ ──→ GitHub Pages
tasker-contrib/ ────┘
```

### Directory Structure
- **`src/`** - mdBook source directory (mix of hand-written and synced content)
  - `getting-started/` - Hand-written consumer guides
  - `stories/` - Hand-written blog series (being rewritten)
  - `architecture/`, `guides/`, `workers/`, etc. - Synced from tasker-core/docs
  - `generated/` - Config reference docs (synced from tasker-core/docs/generated)
  - `contrib/` - Synced from tasker-contrib
- **`cargo-make/scripts/`** - Sync and generation scripts
- **`archive/`** - Old GitBook-era blog posts (not published)
- **`theme/`** - Custom mdBook theme/CSS
- **`book/`** - Build output (gitignored)

### Content Sync
Sync scripts pull from sibling repos with selective exclusions:
- **Included from tasker-core/docs**: architecture, auth, benchmarks, decisions, generated, guides, observability, operations, principles, reference, security, testing, workers
- **Excluded**: ticket-specs (internal), development (contributor-focused), CLAUDE.md files
- **Included from tasker-contrib**: docs/README.md, examples/

### Content Refresh Workflow
1. Create a branch
2. Run `cargo make sync` (requires sibling repos present and up-to-date)
3. Run `cargo make summary` to regenerate SUMMARY.md
4. Run `mdbook serve` to verify locally
5. Commit, push, PR to main
6. Merge triggers GitHub Pages deploy

## Configuration

### Key Files
- **`book.toml`** - mdBook configuration and preprocessors
- **`Makefile.toml`** - cargo-make task definitions
- **`src/SUMMARY.md`** - Auto-generated table of contents
- **`.github/workflows/deploy.yml`** - CI/CD pipeline

### Environment Variables
- `TASKER_CORE_DIR` - Path to tasker-core (default: `../tasker-core`)
- `TASKER_CONTRIB_DIR` - Path to tasker-contrib (default: `../tasker-contrib`)

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
