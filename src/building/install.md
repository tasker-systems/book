# Installation

This guide covers installing Tasker components for development.

## Prerequisites

- **Docker** and **Docker Compose V2** (for Tasker infrastructure)
- **Rust toolchain** (for installing `tasker-ctl`)
- A language runtime for your workers: **Ruby 3.2+**, **Python 3.10+**, **Bun 1.0+** (or Node 18+), or **Rust 1.75+**

## Install tasker-ctl

`tasker-ctl` is the CLI tool for scaffolding projects, generating handlers, and managing configuration:

```bash
cargo install tasker-ctl
```

Verify the installation:

```bash
tasker-ctl --version
# tasker-ctl 0.1.4
```

> **Apple Silicon note**: The published Docker images on GHCR are currently x86_64 only. On Apple Silicon Macs, enable "Use Rosetta for x86\_64/amd64 emulation" in Docker Desktop settings, or ensure your `docker-compose.yml` includes `platform: linux/amd64` on Tasker service containers.

## Installing Worker Packages

Install the package for your language of choice:

### Ruby

```bash
gem install tasker-rb
```

Or add to your Gemfile:

```ruby
gem 'tasker-rb', '~> 0.1.5'
```

### Python

```bash
pip install tasker-py
```

Or with uv:

```bash
uv add tasker-py
```

### TypeScript / JavaScript

```bash
bun add @tasker-systems/tasker
```

Or with npm:

```bash
npm install @tasker-systems/tasker
```

### Rust

Add to your `Cargo.toml`:

```toml
[dependencies]
tasker-worker = "0.1.5"
tasker-client = "0.1.5"
```

## Infrastructure with Docker Compose

Tasker requires PostgreSQL (with the PGMQ extension) and an orchestration service. The fastest way to get these running is Docker Compose.

You can generate a compose file with `tasker-ctl`:

```bash
tasker-ctl init
tasker-ctl remote update
tasker-ctl template generate docker_compose \
  --plugin tasker-contrib-ops \
  --param name=myproject
```

Or use the pre-configured stack from the [example apps](../getting-started/example-apps.md):

```bash
git clone https://github.com/tasker-systems/tasker-contrib.git
cd tasker-contrib/examples
docker compose up -d
```

This starts PostgreSQL (with PGMQ), the Tasker orchestration engine, RabbitMQ, and Dragonfly (cache). The orchestration API is available at `http://localhost:8080`.

### Verify services are running

```bash
curl -sf http://localhost:8080/health
```

## Configuration

Tasker uses environment variables and TOML configuration files. Key environment variables:

```bash
# Database connection (required)
export DATABASE_URL="postgresql://tasker:tasker@localhost:5432/tasker"

# Orchestration API URL (for client SDKs and tasker-ctl)
export ORCHESTRATION_URL="http://localhost:8080"

# Messaging backend: "pgmq" (default, uses PostgreSQL) or "rabbitmq"
export TASKER_MESSAGING_BACKEND="pgmq"
```

For full configuration management, see [Configuration Management](../guides/configuration-management.md) or generate annotated config files with `tasker-ctl config generate`.

## Next Steps

- [Quick Start](quick-start.md) — Two paths to a running workflow
- [Using tasker-ctl](tasker-ctl.md) — Project scaffolding and template generation
- [Your First Handler](first-handler.md) — Write your first step handler
