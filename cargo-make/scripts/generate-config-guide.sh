#!/usr/bin/env bash
# =============================================================================
# Generate Configuration Operational Guide
# =============================================================================
#
# Parses Rust configuration struct definitions from tasker-core and generates
# an operational tuning guide. Uses Ollama for AI-powered guidance when
# available, falls back to deterministic doc-comment extraction.
#
# This generator is opt-in and NOT part of the default `generate` pipeline.
# Run explicitly: cargo make generate-config-guide
#
# Environment (via .env or shell):
#   TASKER_CORE_DIR - Path to tasker-core repo (default: ../tasker-core)
#   OLLAMA_MODEL    - Ollama model to use (default: qwen2.5:14b)
#   SKIP_LLM        - Set to "true" to skip Ollama even if available
#
# Compatible with macOS bash 3.2 (no associative arrays or GNU extensions).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT="${REPO_ROOT}/src/generated/config-operational-guide.md"

# ---------------------------------------------------------------------------
# Source .env if present (won't override existing env vars)
# ---------------------------------------------------------------------------
if [[ -f "${REPO_ROOT}/.env" ]]; then
    while IFS= read -r line; do
        case "${line}" in
            "#"*|"") continue ;;
        esac
        key=$(echo "${line}" | sed -E 's/^([A-Z_]+)=.*/\1/')
        if [[ -z "${!key:-}" ]]; then
            eval "export ${line}"
        fi
    done < "${REPO_ROOT}/.env"
fi

CORE_DIR="${TASKER_CORE_DIR:-../tasker-core}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:14b}"

# Resolve relative path from repo root
if [[ ! "${CORE_DIR}" = /* ]]; then
    CORE_DIR="${REPO_ROOT}/${CORE_DIR}"
fi

CONFIG_FILE="${CORE_DIR}/tasker-shared/src/config/tasker.rs"

# Validate source exists
if [[ ! -f "${CONFIG_FILE}" ]]; then
    echo "ERROR: Config file not found at ${CONFIG_FILE}"
    echo "Set TASKER_CORE_DIR to point to your tasker-core checkout."
    exit 1
fi

echo "Generating configuration operational guide..."
echo "  Source: ${CONFIG_FILE}"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# ---------------------------------------------------------------------------
# Check for Ollama availability
# ---------------------------------------------------------------------------
USE_OLLAMA=false
if [[ "${SKIP_LLM:-false}" != "true" ]] && command -v ollama &>/dev/null; then
    if curl -s --connect-timeout 2 http://localhost:11434/api/tags &>/dev/null; then
        USE_OLLAMA=true
        echo "  Ollama detected (model: ${OLLAMA_MODEL}) - using AI-powered guidance"
    else
        echo "  Ollama installed but not running - using deterministic extraction"
    fi
else
    echo "  Using deterministic extraction (Ollama not available or SKIP_LLM=true)"
fi

# ---------------------------------------------------------------------------
# Find section boundaries dynamically
# ---------------------------------------------------------------------------
COMMON_LINE=$(grep -n "COMMON CONFIGURATION" "${CONFIG_FILE}" | head -1 | cut -d: -f1)
ORCH_LINE=$(grep -n "ORCHESTRATION CONFIGURATION" "${CONFIG_FILE}" | head -1 | cut -d: -f1)
WORKER_LINE=$(grep -n "WORKER CONFIGURATION" "${CONFIG_FILE}" | head -1 | cut -d: -f1)
FILE_END=$(wc -l < "${CONFIG_FILE}" | tr -d ' ')

if [[ -z "${COMMON_LINE}" ]] || [[ -z "${ORCH_LINE}" ]] || [[ -z "${WORKER_LINE}" ]]; then
    echo "ERROR: Could not find section markers in config file"
    exit 1
fi

echo "  Sections: Common (L${COMMON_LINE}), Orchestration (L${ORCH_LINE}), Worker (L${WORKER_LINE})"

# ---------------------------------------------------------------------------
# Helper: Extract deterministic summary from a config section
# ---------------------------------------------------------------------------
deterministic_config_section() {
    local content_file="$1"
    local section_name="$2"

    echo "### ${section_name}"
    echo ""

    # Extract struct definitions with doc comments
    local current_doc=""
    local in_struct=false
    local struct_name=""
    local field_count=0

    while IFS= read -r line; do
        # Collect doc comments
        if [[ "${line}" =~ ^[[:space:]]*/// ]]; then
            local doc_line
            doc_line=$(echo "${line}" | sed -E 's/^[[:space:]]*\/\/\/[[:space:]]?//')
            if [[ -n "${current_doc}" ]]; then
                current_doc="${current_doc} ${doc_line}"
            else
                current_doc="${doc_line}"
            fi
            continue
        fi

        # Match struct definition
        if [[ "${line}" =~ ^pub[[:space:]]+struct[[:space:]]+ ]]; then
            struct_name=$(echo "${line}" | sed -E 's/^pub struct ([A-Za-z0-9_]+).*/\1/')
            in_struct=true
            field_count=0

            echo "**${struct_name}**"
            if [[ -n "${current_doc}" ]]; then
                # Take first sentence only
                local first_sentence
                first_sentence=$(echo "${current_doc}" | sed -E 's/\. .*/\./')
                if [[ ${#first_sentence} -gt 200 ]]; then
                    first_sentence="${first_sentence:0:197}..."
                fi
                echo ": ${first_sentence}"
            fi
            echo ""
            current_doc=""
            continue
        fi

        # Count fields in struct
        if [[ "${in_struct}" == true ]]; then
            if [[ "${line}" =~ ^[[:space:]]*pub[[:space:]] ]]; then
                field_count=$((field_count + 1))
            fi
            if [[ "${line}" =~ ^\} ]]; then
                if [[ ${field_count} -gt 0 ]]; then
                    echo "  ${field_count} configurable parameters"
                    echo ""
                fi
                in_struct=false
            fi
        fi

        # Reset doc if not followed by struct
        if [[ ! "${line}" =~ ^[[:space:]]*# ]] && [[ ! "${line}" =~ ^[[:space:]]*$ ]]; then
            current_doc=""
        fi
    done < "${content_file}"
}

# ---------------------------------------------------------------------------
# Helper: Get Ollama guide for a config section
# ---------------------------------------------------------------------------
ollama_config_guide() {
    local section_name="$1"
    local content_file="$2"

    # Truncate content to ~4000 chars for quality
    local content
    content=$(head -c 4000 "${content_file}")

    local payload_file="${TMPDIR_WORK}/payload.json"
    local response_file="${TMPDIR_WORK}/response.json"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
section = sys.argv[1]
content = sys.argv[2]
prompt = f'''You are documenting the configuration system for Tasker, a Rust-based workflow orchestration platform.

Below is the Rust source code for the {section} configuration section. Generate a concise operational tuning guide in markdown format.

For the most important parameters (skip trivial ones), explain:
1. What it controls
2. When to increase or decrease it
3. Recommended values for small (dev/test), medium (staging), and large (production) deployments

Use markdown tables where appropriate. Start with a brief overview paragraph, then cover the key parameters. Keep the total output under 800 words. Do not include the section title - just the content.

Source code:
{content}'''
json.dump({'model': sys.argv[3], 'prompt': prompt, 'stream': False}, sys.stdout)
" "${section_name}" "${content}" "${OLLAMA_MODEL}" > "${payload_file}"
    else
        echo "  WARNING: python3 required for LLM config guide generation" >&2
        deterministic_config_section "${content_file}" "${section_name}"
        return
    fi

    if curl -s --max-time 120 http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "@${payload_file}" \
        -o "${response_file}" 2>/dev/null; then

        local guide=""
        guide=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print(data.get('response', '').strip())
except: pass
" "${response_file}" 2>/dev/null || echo "")

        if [[ -n "${guide}" ]]; then
            # Clean up pipe chars that break markdown tables
            guide=$(echo "${guide}" | sed 's/  */ /g')
            echo "${guide}"
            return
        fi
    fi

    # Fallback to deterministic
    deterministic_config_section "${content_file}" "${section_name}"
}

# ---------------------------------------------------------------------------
# Extract sections and generate guide
# ---------------------------------------------------------------------------

# Extract each section into temp files
ORCH_END=$((WORKER_LINE - 1))
WORKER_END=$((FILE_END))

sed -n "${COMMON_LINE},${ORCH_LINE}p" "${CONFIG_FILE}" > "${TMPDIR_WORK}/common.rs"
sed -n "${ORCH_LINE},${ORCH_END}p" "${CONFIG_FILE}" > "${TMPDIR_WORK}/orchestration.rs"
sed -n "${WORKER_LINE},${WORKER_END}p" "${CONFIG_FILE}" > "${TMPDIR_WORK}/worker.rs"

# Count structs per section
common_structs=$(grep -c "^pub struct" "${TMPDIR_WORK}/common.rs" || echo "0")
orch_structs=$(grep -c "^pub struct" "${TMPDIR_WORK}/orchestration.rs" || echo "0")
worker_structs=$(grep -c "^pub struct" "${TMPDIR_WORK}/worker.rs" || echo "0")

echo "  Found: ${common_structs} common, ${orch_structs} orchestration, ${worker_structs} worker structs"

# ---------------------------------------------------------------------------
# Generate output
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "${OUTPUT}")"

{
    cat <<'HEADER'
# Configuration Operational Guide

> Auto-generated operational tuning guide. Do not edit manually.
>
> Regenerate with: `cargo make generate-config-guide`

This guide provides operational tuning advice for the most important Tasker
configuration parameters. For the complete parameter reference, see the
[Configuration Reference](config-reference-complete.md).

Tasker uses a context-based configuration architecture:
- **Common** — shared across all contexts (database, queues, resilience, caching)
- **Orchestration** — orchestration-specific (gRPC, web, event systems, DLQ, batch processing)
- **Worker** — worker-specific (event systems, FFI dispatch, circuit breakers)

---

HEADER

    # --- Common Section ---
    echo "## Common Configuration"
    echo ""

    if [[ "${USE_OLLAMA}" == true ]]; then
        echo "  [1/3] Generating common config guide..." >&2
        ollama_config_guide "Common" "${TMPDIR_WORK}/common.rs"
    else
        deterministic_config_section "${TMPDIR_WORK}/common.rs" "Common"
    fi

    echo ""
    echo "---"
    echo ""

    # --- Orchestration Section ---
    echo "## Orchestration Configuration"
    echo ""

    if [[ "${USE_OLLAMA}" == true ]]; then
        echo "  [2/3] Generating orchestration config guide..." >&2
        ollama_config_guide "Orchestration" "${TMPDIR_WORK}/orchestration.rs"
    else
        deterministic_config_section "${TMPDIR_WORK}/orchestration.rs" "Orchestration"
    fi

    echo ""
    echo "---"
    echo ""

    # --- Worker Section ---
    echo "## Worker Configuration"
    echo ""

    if [[ "${USE_OLLAMA}" == true ]]; then
        echo "  [3/3] Generating worker config guide..." >&2
        ollama_config_guide "Worker" "${TMPDIR_WORK}/worker.rs"
    else
        deterministic_config_section "${TMPDIR_WORK}/worker.rs" "Worker"
    fi

    echo ""
    echo "---"
    echo ""

    if [[ "${USE_OLLAMA}" == true ]]; then
        echo "> Operational guidance generated with Ollama (\`${OLLAMA_MODEL}\`). Set \`SKIP_LLM=true\` for deterministic output."
    else
        echo "> Struct summaries extracted deterministically from doc comments."
    fi

    echo ""
    echo "---"
    echo ""
    echo "*Generated by \`generate-config-guide.sh\` from tasker-core configuration source*"

} > "${OUTPUT}"

echo "  Output: ${OUTPUT}"
echo "Configuration operational guide generated (${common_structs} + ${orch_structs} + ${worker_structs} structs)."
