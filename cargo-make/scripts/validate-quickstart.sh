#!/usr/bin/env bash
# validate-quickstart.sh — Structured verification of the Tasker quick-start flow
#
# This script exercises every command documented in the building/ pages,
# capturing output for use as documentation source material.
#
# Usage:
#   cargo make validate-quickstart                    # Non-interactive (CI / cargo-make)
#   cargo make vq                                     # Alias
#
# Direct invocation:
#   bash cargo-make/scripts/validate-quickstart.sh                    # Interactive, all sections
#   bash cargo-make/scripts/validate-quickstart.sh --non-interactive  # Skip prompts (CI)
#   bash cargo-make/scripts/validate-quickstart.sh --section 2        # Run only section N
#
# Sections:
#   1  Prerequisites
#   2  Bootstrap (tasker-ctl init, remote, templates)
#   3  Infrastructure Generation (docker_compose, config from base)
#   4  Start Services (docker compose up, health checks)
#   5  Template Generation — All Languages
#   6  Path A Verification (example apps)
#   7  Cleanup
#   8  Report
set -euo pipefail

# ─── Configuration ──────────────────────────────────────────────────────────

INTERACTIVE=true
RUN_SECTION=""
REPORT_DIR=""
WORK_DIR=""
EXAMPLES_DIR=""
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Contrib sibling directory (workspace co-location)
# Resolve to absolute path since we cd into temp directories later
_contrib_candidate="${TASKER_CONTRIB_DIR:-${REPO_ROOT}/../tasker-contrib}"
if [[ -d "$_contrib_candidate" ]]; then
    CONTRIB_DIR="$(cd "$_contrib_candidate" && pwd)"
else
    CONTRIB_DIR="$_contrib_candidate"
fi

# tasker-ctl binary (override via env for CI or local builds)
TASKER_CTL="${TASKER_CTL:-tasker-ctl}"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Track results for final report (bash 3 compatible — file-based)
RESULTS_FILE=""

# ─── Argument Parsing ───────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive) INTERACTIVE=false; shift ;;
        --section)         RUN_SECTION="$2"; shift 2 ;;
        -h|--help)
            head -30 "$0" | tail -28
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# ─── Helpers ────────────────────────────────────────────────────────────────

header() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

subheader() {
    echo -e "\n${CYAN}── $1 ──${NC}\n"
}

ok() {
    echo -e "  ${GREEN}✓${NC} $1"
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
}

run_cmd() {
    local description="$1"
    shift
    echo -e "  ${CYAN}\$${NC} $*"
    if output=$("$@" 2>&1); then
        ok "$description"
        echo "$output"
        return 0
    else
        fail "$description (exit $?)"
        echo "$output"
        return 1
    fi
}

capture() {
    # Save command output to report directory
    # Usage: capture "filename.ext" command args...
    local filename="$1"
    shift
    local output
    output=$("$@" 2>&1) || true
    echo "$output" > "$REPORT_DIR/$filename"
    echo "$output"
}

prompt_continue() {
    if [[ "$INTERACTIVE" == "true" ]]; then
        echo ""
        echo -e "  ${YELLOW}Press Enter to continue (or Ctrl+C to abort)...${NC}"
        read -r
    fi
}

should_run() {
    local section="$1"
    if [[ -n "$RUN_SECTION" ]]; then
        [[ "$RUN_SECTION" == "$section" ]]
    else
        return 0
    fi
}

record_result() {
    local section="$1"
    local status="$2"
    echo "$section=$status" >> "$RESULTS_FILE"
}

# ─── Cleanup Trap ───────────────────────────────────────────────────────────

cleanup() {
    echo ""
    echo -e "${YELLOW}Cleaning up...${NC}"

    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        # Stop docker compose in work directory
        if [[ -f "$WORK_DIR/docker-compose.yml" ]]; then
            (cd "$WORK_DIR" && docker compose down -v 2>/dev/null) || true
        fi
    fi

    if [[ -n "$EXAMPLES_DIR" && -d "$EXAMPLES_DIR" ]]; then
        (cd "$EXAMPLES_DIR" && docker compose down -v 2>/dev/null) || true
    fi

    if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
        echo -e "  ${GREEN}✓${NC} Removed temp directory"
    fi
}

trap cleanup EXIT

# ─── Setup ──────────────────────────────────────────────────────────────────

REPORT_DIR=$(mktemp -d)/quick-start-report
mkdir -p "$REPORT_DIR"
RESULTS_FILE="$REPORT_DIR/results.txt"
touch "$RESULTS_FILE"
echo -e "${BOLD}Report directory:${NC} $REPORT_DIR"

# ═══════════════════════════════════════════════════════════════════════════
# Section 1: Prerequisites
# Maps to: building/install.md
# ═══════════════════════════════════════════════════════════════════════════

if should_run 1; then
    header "Section 1: Prerequisites"

    subheader "Core Tools"

    # tasker-ctl
    if command -v "$TASKER_CTL" &>/dev/null; then
        version=$("$TASKER_CTL" --version 2>&1 || echo "unknown")
        ok "tasker-ctl: $version"
        echo "$version" > "$REPORT_DIR/tasker-ctl-version.txt"
        record_result "tasker-ctl" "OK"
    else
        fail "tasker-ctl not found — install with: cargo install tasker-ctl"
        record_result "tasker-ctl" "MISSING"
    fi

    # Docker
    if command -v docker &>/dev/null; then
        version=$(docker --version 2>&1)
        ok "docker: $version"
        record_result "docker" "OK"
    else
        fail "docker not found — required for quick-start validation"
        record_result "docker" "MISSING"
        exit 1
    fi

    # Docker Compose
    if docker compose version &>/dev/null; then
        version=$(docker compose version 2>&1)
        ok "docker compose: $version"
        record_result "docker-compose" "OK"
    else
        fail "docker compose not found (requires Docker Compose V2)"
        record_result "docker-compose" "MISSING"
        exit 1
    fi

    subheader "Language Runtimes"

    # Ruby
    if command -v ruby &>/dev/null; then
        version=$(ruby --version 2>&1)
        ok "ruby: $version"
        record_result "ruby" "OK"
    else
        warn "ruby not found (needed for Ruby handlers)"
        record_result "ruby" "MISSING"
    fi

    # Python
    if command -v python3 &>/dev/null; then
        version=$(python3 --version 2>&1)
        ok "python3: $version"
        record_result "python3" "OK"
    else
        warn "python3 not found (needed for Python handlers)"
        record_result "python3" "MISSING"
    fi

    # Bun or Node
    if command -v bun &>/dev/null; then
        version=$(bun --version 2>&1)
        ok "bun: $version"
        record_result "bun" "OK"
    elif command -v node &>/dev/null; then
        version=$(node --version 2>&1)
        ok "node: $version (bun recommended)"
        record_result "node" "OK"
    else
        warn "bun/node not found (needed for TypeScript handlers)"
        record_result "bun" "MISSING"
    fi

    # Rust
    if command -v rustc &>/dev/null; then
        version=$(rustc --version 2>&1)
        ok "rustc: $version"
        record_result "rustc" "OK"
    else
        warn "rustc not found (needed for Rust handlers)"
        record_result "rustc" "MISSING"
    fi

    subheader "Platform Detection"

    arch=$(uname -m)
    os=$(uname -s)
    echo -e "  Platform: ${BOLD}$os $arch${NC}"

    if [[ "$arch" == "arm64" ]]; then
        warn "Apple Silicon detected — GHCR images require Rosetta"
        warn "Docker must have 'Use Rosetta' enabled or images need platform: linux/amd64"
        record_result "platform" "Apple Silicon"
    else
        ok "x86_64 — GHCR images run natively"
        record_result "platform" "x86_64"
    fi

    prompt_continue
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 2: Bootstrap with tasker-ctl
# Maps to: building/quick-start.md Path B, building/tasker-ctl.md
# ═══════════════════════════════════════════════════════════════════════════

if should_run 2; then
    header "Section 2: Bootstrap with tasker-ctl"

    if ! command -v "$TASKER_CTL" &>/dev/null; then
        fail "tasker-ctl not found — skipping bootstrap section"
        record_result "bootstrap" "SKIPPED"
    else
        # Create temp working directory
        WORK_DIR=$(mktemp -d)
        echo -e "  Working directory: ${BOLD}$WORK_DIR${NC}"
        cd "$WORK_DIR"

        subheader "Initialize Project"
        run_cmd "tasker-ctl init" "$TASKER_CTL" init || true

        if [[ -f .tasker-ctl.toml ]]; then
            ok ".tasker-ctl.toml created"
        else
            fail ".tasker-ctl.toml not created"
        fi

        # Point at local tasker-contrib for template discovery
        # This validates the actual local templates, not the remote cache
        if [[ -d "$CONTRIB_DIR" ]]; then
            cat > .tasker-ctl.toml <<EOF
plugin-paths = ["$CONTRIB_DIR"]
EOF
            ok "Configured local plugin path: $CONTRIB_DIR"
        else
            warn "tasker-contrib not found at $CONTRIB_DIR — falling back to remote"
            run_cmd "tasker-ctl remote update" "$TASKER_CTL" remote update || true
        fi

        capture "init-config.toml" cat .tasker-ctl.toml

        subheader "List All Templates"
        capture "template-list-all.txt" "$TASKER_CTL" template list
        echo ""
        cat "$REPORT_DIR/template-list-all.txt"

        subheader "List Templates by Language"
        for lang in ruby python typescript rust; do
            echo -e "  ${CYAN}Language: $lang${NC}"
            capture "template-list-$lang.txt" "$TASKER_CTL" template list --language "$lang"
            cat "$REPORT_DIR/template-list-$lang.txt"
            echo ""
        done

        record_result "bootstrap" "OK"
        prompt_continue
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 3: Infrastructure Generation
# Maps to: building/quick-start.md Path B, building/install.md
# ═══════════════════════════════════════════════════════════════════════════

if should_run 3; then
    header "Section 3: Infrastructure Generation"

    if ! command -v "$TASKER_CTL" &>/dev/null; then
        fail "tasker-ctl not found — skipping"
        record_result "infra-gen" "SKIPPED"
    else
        # Ensure we're in a work directory
        if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
            WORK_DIR=$(mktemp -d)
            cd "$WORK_DIR"
            "$TASKER_CTL" init 2>/dev/null || true
            if [[ -d "$CONTRIB_DIR" ]]; then
                cat > .tasker-ctl.toml <<EOF
plugin-paths = ["$CONTRIB_DIR"]
EOF
            else
                "$TASKER_CTL" remote update 2>/dev/null || true
            fi
        fi
        cd "$WORK_DIR"

        subheader "Generate Docker Compose"
        run_cmd "Generate docker_compose" \
            "$TASKER_CTL" template generate docker_compose \
            --plugin tasker-contrib-ops \
            --param name=quickstart || true

        if [[ -f docker-compose.yml ]]; then
            ok "docker-compose.yml generated"
            capture "generated-docker-compose.yml" cat docker-compose.yml

            # Inspect for known gaps
            echo ""
            echo -e "  ${CYAN}Inspecting generated docker-compose.yml:${NC}"

            if grep -q ":latest" docker-compose.yml; then
                warn "Uses :latest tags (examples pin to 0.1.5 / pg18-latest)"
            fi

            if ! grep -q "platform:" docker-compose.yml; then
                warn "Missing platform: linux/amd64 (needed for Apple Silicon)"
            fi

            if ! grep -q "TASKER_CONFIG_PATH" docker-compose.yml; then
                warn "No TASKER_CONFIG_PATH env var (config files won't be loaded)"
            fi

            if ! grep -q "./config:/app/config" docker-compose.yml; then
                warn "No config volume mount for orchestration container"
            fi
        else
            fail "docker-compose.yml not generated"
        fi

        subheader "Generate Configuration Files"
        mkdir -p config

        config_source_args=()
        if [[ -d "$CONTRIB_DIR/config/tasker" ]]; then
            config_source_args=(--source-dir "$CONTRIB_DIR/config/tasker")
        else
            config_source_args=(--remote tasker-contrib)
        fi

        run_cmd "Generate orchestration config" \
            "$TASKER_CTL" config generate "${config_source_args[@]}" \
            --context orchestration --environment development \
            --output config/orchestration.toml || true

        run_cmd "Generate worker config" \
            "$TASKER_CTL" config generate "${config_source_args[@]}" \
            --context worker --environment development \
            --output config/worker.toml || true

        for f in config/orchestration.toml config/worker.toml; do
            if [[ -f "$f" ]]; then
                ok "$(basename "$f") generated"
                capture "generated-$(basename "$f")" cat "$f"
            else
                warn "$(basename "$f") not generated"
            fi
        done

        record_result "infra-gen" "OK"
        prompt_continue
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 4: Start Services
# Maps to: building/install.md, building/quick-start.md
# ═══════════════════════════════════════════════════════════════════════════

if should_run 4; then
    header "Section 4: Start Services"

    if [[ -z "$WORK_DIR" || ! -f "$WORK_DIR/docker-compose.yml" ]]; then
        fail "No docker-compose.yml found — run sections 2-3 first"
        record_result "services" "SKIPPED"
    else
        cd "$WORK_DIR"

        subheader "Start Docker Compose Stack"
        run_cmd "docker compose up" docker compose up -d || true

        subheader "Wait for Health"
        echo "  Waiting for orchestration service at http://localhost:8080/health ..."
        healthy=false
        for i in $(seq 1 12); do
            if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
                healthy=true
                break
            fi
            echo "  ... attempt $i/12 (waiting 5s)"
            sleep 5
        done

        if [[ "$healthy" == "true" ]]; then
            ok "Orchestration service healthy"
            capture "health-response.json" curl -s http://localhost:8080/health
        else
            fail "Orchestration service not healthy after 60s"
        fi

        subheader "tasker-ctl system health"
        if command -v "$TASKER_CTL" &>/dev/null; then
            # Need to set base URL for the CLI client
            export ORCHESTRATION_URL=http://localhost:8080
            capture "system-health.json" "$TASKER_CTL" system health || true
            cat "$REPORT_DIR/system-health.json"
        fi

        record_result "services" "$([ "$healthy" == "true" ] && echo "OK" || echo "FAIL")"
        prompt_continue
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 5: Template Generation — All Languages
# Maps to: building/first-handler.md, language guides
# ═══════════════════════════════════════════════════════════════════════════

if should_run 5; then
    header "Section 5: Template Generation — All Languages"

    if ! command -v "$TASKER_CTL" &>/dev/null; then
        fail "tasker-ctl not found — skipping"
        record_result "templates" "SKIPPED"
    else
        if [[ -z "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
            WORK_DIR=$(mktemp -d)
            cd "$WORK_DIR"
            "$TASKER_CTL" init 2>/dev/null || true
            if [[ -d "$CONTRIB_DIR" ]]; then
                cat > .tasker-ctl.toml <<EOF
plugin-paths = ["$CONTRIB_DIR"]
EOF
            else
                "$TASKER_CTL" remote update 2>/dev/null || true
            fi
        fi
        cd "$WORK_DIR"

        # File extension per language (for capture filenames)
        ext_for() {
            case $1 in
                ruby) echo "rb" ;; python) echo "py" ;;
                typescript) echo "ts" ;; rust) echo "rs" ;;
            esac
        }

        # Handler templates available per language
        # Rust only has step_handler; others have all four variants
        handler_templates_for() {
            case $1 in
                rust) echo "step_handler" ;;
                *)    echo "step_handler step_handler_api step_handler_decision step_handler_batchable" ;;
            esac
        }

        # Template param "name" per handler type
        handler_name_for() {
            case $1 in
                step_handler)          echo "ProcessOrder" ;;
                step_handler_api)      echo "FetchUser" ;;
                step_handler_decision) echo "RouteOrder" ;;
                step_handler_batchable) echo "ProcessBatch" ;;
            esac
        }

        # Syntax check a generated file
        syntax_check() {
            local lang="$1" filepath="$2"
            case $lang in
                ruby)
                    if command -v ruby &>/dev/null; then
                        if ruby -c "$filepath" > /dev/null 2>&1; then
                            ok "Ruby syntax check passed: $(basename "$filepath")"
                        else
                            fail "Ruby syntax check failed: $(basename "$filepath")"
                        fi
                    fi
                    ;;
                python)
                    if command -v python3 &>/dev/null; then
                        if python3 -c "import py_compile; py_compile.compile('$filepath', doraise=True)" 2>/dev/null; then
                            ok "Python syntax check passed: $(basename "$filepath")"
                        else
                            fail "Python syntax check failed: $(basename "$filepath")"
                        fi
                    fi
                    ;;
                typescript)
                    ok "TypeScript file generated: $(basename "$filepath") (syntax check requires tsc)"
                    ;;
                rust)
                    ok "Rust file generated: $(basename "$filepath") (syntax check requires cargo)"
                    ;;
            esac
        }

        for lang in ruby python typescript rust; do
            subheader "Language: $lang"

            ext=$(ext_for "$lang")
            handler_callable_prefix=""
            case $lang in
                ruby)       handler_callable_prefix="Handlers::" ;;
                python)     handler_callable_prefix="handlers." ;;
                typescript) handler_callable_prefix="" ;;
                rust)       handler_callable_prefix="" ;;
            esac

            # Generate all handler templates for this language
            for tmpl in $(handler_templates_for "$lang"); do
                tmpl_name=$(handler_name_for "$tmpl")
                local_dir="$WORK_DIR/$lang/$tmpl"
                mkdir -p "$local_dir"

                echo -e "  ${CYAN}Generating $tmpl...${NC}"
                run_cmd "$tmpl ($lang)" \
                    "$TASKER_CTL" template generate "$tmpl" \
                    --language "$lang" \
                    --param name="$tmpl_name" \
                    --output "$local_dir" || true

                # Capture each generated handler file (not tests/specs)
                find "$local_dir" -type f -name "*" | sort | while read -r f; do
                    fname=$(basename "$f")
                    # Skip test/spec files for capture (they're still generated)
                    case "$fname" in
                        *test*|*spec*) ;;
                        *)
                            capture "$tmpl-$lang.$ext" cat "$f"
                            syntax_check "$lang" "$f"
                            ;;
                    esac
                done
            done

            # Generate task template
            case $lang in
                ruby)       callable="${handler_callable_prefix}ProcessOrderHandler" ;;
                python)     callable="handlers.process_order_handler.ProcessOrderHandler" ;;
                typescript) callable="ProcessOrderHandler" ;;
                rust)       callable="process_order" ;;
            esac

            task_dir="$WORK_DIR/$lang/task_template"
            mkdir -p "$task_dir"

            echo -e "  ${CYAN}Generating task_template...${NC}"
            run_cmd "task_template ($lang)" \
                "$TASKER_CTL" template generate task_template \
                --language "$lang" \
                --param name=OrderProcessing \
                --param namespace=default \
                --param handler_callable="$callable" \
                --output "$task_dir" || true

            # Capture the generated YAML
            task_file=$(find "$task_dir" -name "*.yaml" -o -name "*.yml" | head -1)
            if [[ -n "$task_file" ]]; then
                capture "task-template-$lang.yaml" cat "$task_file"
            fi

            # List all generated files for this language
            echo -e "\n  ${CYAN}All generated files ($lang):${NC}"
            find "$WORK_DIR/$lang" -type f | sort | while read -r f; do
                echo "    ${f#$WORK_DIR/$lang/}"
            done

            echo ""
            record_result "template-$lang" "OK"
        done

        prompt_continue
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 6: Path A Verification — Example Apps
# Maps to: building/quick-start.md Path A
# ═══════════════════════════════════════════════════════════════════════════

if should_run 6; then
    header "Section 6: Path A — Example Apps"

    EXAMPLES_DIR="$CONTRIB_DIR/examples"

    if [[ ! -d "$EXAMPLES_DIR" ]]; then
        fail "Examples directory not found at $EXAMPLES_DIR"
        warn "Expected tasker-contrib to be a sibling of tasker-book"
        record_result "path-a" "SKIPPED"
    else
        cd "$EXAMPLES_DIR"

        subheader "Start Example Infrastructure"
        run_cmd "docker compose up" docker compose up -d || true

        subheader "Wait for Health"
        echo "  Waiting for orchestration at http://localhost:8080/health ..."
        healthy=false
        for i in $(seq 1 12); do
            if curl -sf http://localhost:8080/health > /dev/null 2>&1; then
                healthy=true
                break
            fi
            echo "  ... attempt $i/12 (waiting 5s)"
            sleep 5
        done

        if [[ "$healthy" == "true" ]]; then
            ok "Example infrastructure healthy"
            capture "examples-health.json" curl -s http://localhost:8080/health
        else
            fail "Example infrastructure not healthy after 60s"
        fi

        if [[ "$healthy" == "true" ]]; then
            subheader "Submit a Task via REST API"

            # Use the ecommerce order processing task template
            task_json='{
                "name": "ecommerce_order_processing",
                "namespace": "ecommerce_rb",
                "version": "1.0.0",
                "initiator": "verify-script",
                "source_system": "cli",
                "reason": "Quick-start verification",
                "context": {
                    "cart_items": [
                        {"sku": "WIDGET-001", "name": "Widget", "quantity": 2, "unit_price": 29.99}
                    ],
                    "customer_email": "test@example.com"
                }
            }'

            echo -e "  ${CYAN}POST /api/v1/tasks${NC}"
            response=$(curl -s -w "\n%{http_code}" \
                -X POST http://localhost:8080/api/v1/tasks \
                -H "Content-Type: application/json" \
                -d "$task_json")

            http_code=$(echo "$response" | tail -1)
            body=$(echo "$response" | sed '$d')

            echo "$body" > "$REPORT_DIR/task-create-response.txt"

            if [[ "$http_code" =~ ^2 ]]; then
                ok "Task created (HTTP $http_code)"
                echo "$body" | python3 -m json.tool 2>/dev/null || echo "$body"

                # Extract task UUID for polling
                task_uuid=$(echo "$body" | python3 -c "import sys,json; print(json.load(sys.stdin).get('task_uuid',''))" 2>/dev/null || echo "")

                if [[ -n "$task_uuid" ]]; then
                    subheader "Poll Task Status"
                    echo "  Task UUID: $task_uuid"

                    for i in $(seq 1 10); do
                        sleep 2
                        status_response=$(curl -s "http://localhost:8080/api/v1/tasks/$task_uuid")
                        status=$(echo "$status_response" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','unknown'))" 2>/dev/null || echo "unknown")
                        echo "  ... poll $i: status=$status"

                        if [[ "$status" == "complete" || "$status" == "completed" ]]; then
                            ok "Task completed!"
                            echo "$status_response" > "$REPORT_DIR/task-final-status.txt"
                            echo "$status_response" | python3 -m json.tool 2>/dev/null || echo "$status_response"
                            break
                        elif [[ "$status" == "error" || "$status" == "failed" ]]; then
                            fail "Task failed: $status"
                            echo "$status_response" > "$REPORT_DIR/task-final-status.txt"
                            break
                        fi
                    done
                fi
            else
                fail "Task creation failed (HTTP $http_code)"
                echo "$body"
            fi
        fi

        record_result "path-a" "$([ "$healthy" == "true" ] && echo "OK" || echo "FAIL")"
        prompt_continue
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 7: Cleanup (handled by EXIT trap)
# ═══════════════════════════════════════════════════════════════════════════

if should_run 7; then
    header "Section 7: Cleanup"
    echo "  Cleanup will run automatically on exit."
    record_result "cleanup" "OK"
fi

# ═══════════════════════════════════════════════════════════════════════════
# Section 8: Report
# ═══════════════════════════════════════════════════════════════════════════

if should_run 8 || [[ -z "$RUN_SECTION" ]]; then
    header "Section 8: Verification Report"

    echo -e "  ${BOLD}Results Summary${NC}"
    echo "  ─────────────────────────────────────"

    sort "$RESULTS_FILE" | while IFS='=' read -r key status; do
        case "$status" in
            OK)      echo -e "  ${GREEN}✓${NC} $key: $status" ;;
            MISSING) echo -e "  ${YELLOW}⚠${NC} $key: $status" ;;
            FAIL)    echo -e "  ${RED}✗${NC} $key: $status" ;;
            SKIPPED) echo -e "  ${YELLOW}─${NC} $key: $status" ;;
            *)       echo "  ? $key: $status" ;;
        esac
    done

    echo ""
    echo -e "  ${BOLD}Report files saved to:${NC} $REPORT_DIR"
    echo ""
    ls -la "$REPORT_DIR/" 2>/dev/null || true
fi
