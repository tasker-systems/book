# Contributing to Tasker

This guide covers development setup and workflow for contributing to [tasker-core](https://github.com/tasker-systems/tasker-core) and [tasker-contrib](https://github.com/tasker-systems/tasker-contrib).

## Contributing to tasker-core

### Prerequisites

- **Rust** stable toolchain (via [rustup](https://rustup.rs/))
- **Docker Desktop** (for PostgreSQL, RabbitMQ, and supporting services)
- **cargo-make** (`cargo install cargo-make`)
- Optional: Ruby 3.4+, Python 3.12+, Bun 1.x (for FFI worker development)

On macOS, the project includes a [Brewfile](https://github.com/tasker-systems/tasker-core/blob/main/Brewfile) that installs system dependencies (PostgreSQL 18, protobuf, LLVM, language toolchains).

### Automated Setup

The fastest path is the automated setup script:

```bash
git clone https://github.com/tasker-systems/tasker-core.git
cd tasker-core

# Full setup — installs Homebrew deps, Rust tools, git hooks, worker deps
./bin/setup-dev.sh

# Or run targeted slices
./bin/setup-dev.sh --brew-only     # Homebrew bundle only
./bin/setup-dev.sh --cargo-only    # cargo-make, sqlx-cli, nextest
./bin/setup-dev.sh --hooks-only    # Git pre-commit hook
./bin/setup-dev.sh --check         # Audit what's installed
```

### Starting Services

```bash
# Start PostgreSQL (with PGMQ), RabbitMQ, Dragonfly cache, Grafana LGTM
cargo make docker-up
```

### Database Setup

```bash
cargo make db-setup    # Run migrations
cargo make db-reset    # Drop and recreate (clean slate)
```

### Environment Configuration

Environment variables are assembled from modular files in `config/dotenv/`:

```bash
cargo make setup-env           # Standard test mode
cargo make setup-env-split     # Split database mode
cargo make setup-env-cluster   # Cluster testing mode
```

See `config/dotenv/README.md` for the full file structure and assembly order.

### Key Commands

| Command | Shortcut | What it does |
|---------|----------|--------------|
| `cargo make check` | `c` | Lint + format + build |
| `cargo make test` | `t` | All tests (requires services) |
| `cargo make fix` | `f` | Auto-fix issues |
| `cargo make build` | `b` | Build everything |
| `cargo make test-rust-unit` | `tu` | Unit tests (DB + messaging only) |
| `cargo make test-rust-e2e` | `te` | E2E tests (requires services) |
| `cargo make test-rust-cluster` | `tc` | Cluster tests (multi-instance) |

Always use `--all-features` when running cargo commands directly.

### Test Tiers

Tests are organized into infrastructure levels via feature flags:

| Level | Feature flag | Requires |
|-------|-------------|----------|
| Unit | `test-messaging` | PostgreSQL + messaging |
| E2E | `test-services` | + running services |
| Cluster | `test-cluster` | + multi-instance cluster |

Run `cargo make test-rust-unit` for fast iteration. Run the full suite with `cargo make test` before opening a PR.

### Worker Development

Tasker supports polyglot workers through FFI:

- **Ruby** via [magnus](https://github.com/matsadler/magnus) — `workers/ruby/`
- **Python** via [PyO3](https://pyo3.rs/) — `workers/python/`
- **TypeScript** via [napi-rs](https://napi.rs/) — `workers/typescript/`

Each worker directory has its own build and test commands. See the [Worker Guides](../workers/README.md) for language-specific details.

### SQLx Query Cache

After modifying `sqlx::query!` macros or SQL schema, update the offline cache:

```bash
DATABASE_URL=postgresql://tasker:tasker@localhost:5432/tasker_rust_test \
  cargo sqlx prepare --workspace -- --all-targets --all-features

git add .sqlx/
```

### Conventions

- **Branch naming**: `username/ticket-id-short-description` (e.g., `jcoletaylor/tas-190-add-version-fields`)
- **Commit messages**: `type(scope): description` (e.g., `fix(orchestration): handle timeout in step enqueuer`)
- **Git hooks**: Pre-commit runs `cargo fmt` on staged Rust files. Install with `git config core.hooksPath .githooks` or via `setup-dev.sh`.
- **Lint suppression**: Use `#[expect(lint_name, reason = "...")]` instead of `#[allow]`
- **SQLx**: Never use `SQLX_OFFLINE=true` — always export `DATABASE_URL`
- **Public types**: Must implement `Debug`
- **Channels**: All MPSC channels must be bounded and configured via TOML

### Pull Request Process

1. Branch from `main`
2. Make focused changes (one logical change per PR)
3. Run `cargo make check && cargo make test`
4. Update documentation if your change affects public APIs or behavior
5. Open a PR against `main`

New functionality should include tests. Bug fixes should include a regression test.

---

## Contributing to tasker-contrib

### Prerequisites

- **cargo-make** (`cargo install cargo-make`)
- **tasker-ctl** binary (build from core or `cargo install tasker-ctl`)
- Docker and Docker Compose (for example app testing)
- Language toolchain for the area you're working on (Ruby 3.3+, Python 3.12+, Bun 1.0+, or Rust stable)

### Getting tasker-ctl

```bash
# Option A: Install from crates.io
cargo install tasker-ctl

# Option B: Build from local tasker-core (requires sibling checkout)
cargo make build-ctl
```

### Adding a New Template

Each language plugin lives in `{language}/tasker-cli-plugin/` and follows this structure:

```
{language}/tasker-cli-plugin/
+-- tasker-plugin.toml          # Plugin manifest
+-- templates/
    +-- step_handler/           # Template directory
    |   +-- template.toml       # Metadata and variables
    |   +-- files/              # Tera template files
    +-- step_handler_api/
    +-- task_template/
```

Steps to add a template:

1. Create the template directory under the appropriate plugin
2. Add `template.toml` with metadata and variable definitions
3. Add template files in `files/` using [Tera](https://keats.github.io/tera/) syntax (built-in helpers: `snake_case`, `pascal_case`)
4. Register the template in `tasker-plugin.toml`
5. Run `cargo make test-templates` to verify generation and syntax checking

### Adding a New Example App

1. Create `examples/{framework}-app/` with standard project structure
2. Add the app database to `examples/init-db.sql`
3. Add a `cargo make test-example-{framework}` task to `Makefile.toml`
4. Add the app to the `test-examples` dependencies in `Makefile.toml`
5. Add CI steps to `.github/workflows/test-examples.yml`

### Validation Commands

| Command | Shortcut | What it does |
|---------|----------|--------------|
| `cargo make validate` | `v` | Validate all plugin manifests |
| `cargo make test-templates` | `tt` | Generate + syntax-check all templates |
| `cargo make test-all` | `ta` | Full validation (validate + test-templates) |
| `cargo make test-examples` | `te` | Integration tests for all example apps |

### Example App Infrastructure

The example apps share a Docker Compose stack in `examples/`:

```bash
cd examples
docker compose up -d
```

This starts PostgreSQL 18 (with PGMQ + app databases), Tasker orchestration (from published GHCR images), Dragonfly cache, and RabbitMQ. Wait for orchestration to be healthy before running tests:

```bash
curl -sf http://localhost:8080/health
```

---

## Getting Help

- [Discussions](https://github.com/tasker-systems/tasker-core/discussions) for questions
- [Issues](https://github.com/tasker-systems/tasker-core/issues) for bugs or feature requests
- Both projects follow the [Contributor Covenant 3.0](https://www.contributor-covenant.org/version/3/0/code-of-conduct/) code of conduct
