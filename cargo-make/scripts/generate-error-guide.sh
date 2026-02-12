#!/usr/bin/env bash
# =============================================================================
# Generate Error Troubleshooting Guide
# =============================================================================
#
# Parses Rust error enum definitions from tasker-core and generates a
# troubleshooting guide. Uses Ollama for AI-powered diagnosis and resolution
# advice when available, falls back to deterministic error message extraction.
#
# This generator is opt-in and NOT part of the default `generate` pipeline.
# Run explicitly: cargo make generate-error-guide
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
OUTPUT="${REPO_ROOT}/src/generated/error-troubleshooting-guide.md"

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

ERRORS_FILE="${CORE_DIR}/tasker-shared/src/errors.rs"

# Validate source exists
if [[ ! -f "${ERRORS_FILE}" ]]; then
    echo "ERROR: Errors file not found at ${ERRORS_FILE}"
    echo "Set TASKER_CORE_DIR to point to your tasker-core checkout."
    exit 1
fi

echo "Generating error troubleshooting guide..."
echo "  Source: ${ERRORS_FILE}"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# ---------------------------------------------------------------------------
# Check for Ollama availability
# ---------------------------------------------------------------------------
USE_OLLAMA=false
if [[ "${SKIP_LLM:-false}" != "true" ]] && command -v ollama &>/dev/null; then
    if curl -s --connect-timeout 2 http://localhost:11434/api/tags &>/dev/null; then
        USE_OLLAMA=true
        echo "  Ollama detected (model: ${OLLAMA_MODEL}) - using AI-powered troubleshooting"
    else
        echo "  Ollama installed but not running - using deterministic extraction"
    fi
else
    echo "  Using deterministic extraction (Ollama not available or SKIP_LLM=true)"
fi

# ---------------------------------------------------------------------------
# Extract error enums from source (stop before #[cfg(test)] block)
# ---------------------------------------------------------------------------
# Get the line number where tests start (if any)
TEST_LINE=$(grep -n "^#\[cfg(test)\]" "${ERRORS_FILE}" | head -1 | cut -d: -f1)
if [[ -z "${TEST_LINE}" ]]; then
    TEST_LINE=$(wc -l < "${ERRORS_FILE}" | tr -d ' ')
fi

# Extract just the enum definitions (no tests, no From impls)
# We want: doc comments + pub enum ... { ... }
extract_enums() {
    local file="$1"
    local max_line="$2"
    local enum_index=0

    # Use awk to extract each pub enum block with preceding doc comments
    awk -v max_line="${max_line}" '
    NR > max_line { exit }

    # Collect doc comments
    /^\/\/\// {
        if (collecting_docs == 0) {
            doc_start = NR
            docs = ""
        }
        collecting_docs = 1
        docs = docs $0 "\n"
        next
    }

    # Match pub enum
    /^pub enum/ {
        enum_name = $0
        sub(/pub enum /, "", enum_name)
        sub(/ .*/, "", enum_name)

        # Write to file
        outfile = TMPDIR "/enum_" ++enum_index ".txt"
        namefile = TMPDIR "/name_" enum_index ".txt"

        print enum_name > namefile
        close(namefile)

        if (collecting_docs) {
            printf "%s", docs > outfile
        }
        print $0 > outfile
        in_enum = 1
        brace_depth = 0
        if ($0 ~ /\{/) brace_depth++
        if ($0 ~ /\}/) brace_depth--
        collecting_docs = 0
        docs = ""
        next
    }

    # Inside enum body
    in_enum {
        print $0 > outfile
        if ($0 ~ /\{/) brace_depth++
        if ($0 ~ /\}/) brace_depth--
        if (brace_depth <= 0) {
            close(outfile)
            in_enum = 0
        }
        next
    }

    # Reset doc collection if line is not doc/attr/blank
    !/^[[:space:]]*$/ && !/^[[:space:]]*#/ {
        collecting_docs = 0
        docs = ""
    }
    ' TMPDIR="${TMPDIR_WORK}" "${file}"

    # Count extracted enums by counting name files
    local count=0
    for f in "${TMPDIR_WORK}"/name_*.txt; do
        if [[ -f "${f}" ]]; then
            count=$((count + 1))
        fi
    done
    echo "${count}"
}

ENUM_COUNT=$(extract_enums "${ERRORS_FILE}" "${TEST_LINE}")
echo "  Found ${ENUM_COUNT} error enums"

# ---------------------------------------------------------------------------
# Helper: Extract deterministic summary from an enum
# ---------------------------------------------------------------------------
deterministic_error_section() {
    local enum_file="$1"
    local enum_name="$2"

    echo "### ${enum_name}"
    echo ""

    # Extract variants with their error messages
    echo "| Variant | Error Message |"
    echo "|---------|---------------|"

    local current_doc=""
    while IFS= read -r line; do
        # Capture #[error("...")] message
        if echo "${line}" | grep -q '#\[error('; then
            local msg
            msg=$(echo "${line}" | sed -E 's/.*#\[error\("([^"]+)".*/\1/')
            if [[ "${msg}" == "${line}" ]]; then
                msg="(complex format)"
            fi
            current_doc="${msg}"
            continue
        fi

        # Capture variant name
        if echo "${line}" | grep -qE '^[[:space:]]+([A-Z][A-Za-z]+)'; then
            local variant
            variant=$(echo "${line}" | sed -E 's/^[[:space:]]+([A-Za-z]+).*/\1/')
            # Skip common non-variant patterns
            case "${variant}" in
                "pub"|"fn"|"let"|"use"|"impl"|"where"|"type") continue ;;
            esac
            if [[ -n "${current_doc}" ]]; then
                # Clean pipe chars for table safety
                current_doc=$(echo "${current_doc}" | sed 's/|/—/g')
                echo "| \`${variant}\` | ${current_doc} |"
                current_doc=""
            fi
        fi
    done < "${enum_file}"

    echo ""
}

# ---------------------------------------------------------------------------
# Helper: Get Ollama troubleshooting guide for an error enum
# ---------------------------------------------------------------------------
ollama_error_guide() {
    local enum_name="$1"
    local enum_file="$2"

    local content
    content=$(head -c 3000 "${enum_file}")

    local payload_file="${TMPDIR_WORK}/payload.json"
    local response_file="${TMPDIR_WORK}/response.json"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
enum_name = sys.argv[1]
content = sys.argv[2]
prompt = f'''You are documenting error handling for Tasker, a Rust-based workflow orchestration platform that processes tasks through state machine-driven workflows with polyglot worker support (Rust, Python, TypeScript).

Below is the Rust error enum definition for \`{enum_name}\`. Generate a concise troubleshooting guide in markdown format.

For the most important error variants (group trivial ones), provide:
1. **Likely cause** — what typically triggers this error
2. **Diagnosis** — what logs, metrics, or state to check
3. **Resolution** — concrete steps to fix

Use a markdown table with columns: Variant, Cause, Resolution. Add a brief overview paragraph before the table. Keep output under 600 words. Do not include the section title - just the content.

Error definition:
{content}'''
json.dump({'model': sys.argv[3], 'prompt': prompt, 'stream': False}, sys.stdout)
" "${enum_name}" "${content}" "${OLLAMA_MODEL}" > "${payload_file}"
    else
        echo "  WARNING: python3 required for LLM error guide generation" >&2
        deterministic_error_section "${enum_file}" "${enum_name}"
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
            guide=$(echo "${guide}" | sed 's/  */ /g')
            echo "${guide}"
            return
        fi
    fi

    # Fallback to deterministic
    deterministic_error_section "${enum_file}" "${enum_name}"
}

# ---------------------------------------------------------------------------
# Generate output
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "${OUTPUT}")"

{
    cat <<'HEADER'
# Error Troubleshooting Guide

> Auto-generated troubleshooting guide. Do not edit manually.
>
> Regenerate with: `cargo make generate-error-guide`

This guide provides diagnosis and resolution steps for errors in the Tasker
workflow orchestration system. Errors are organized by subsystem, from
high-level system errors to specific execution and infrastructure errors.

**Error hierarchy**: Most specialized errors convert upward —
`ExecutionError` → `OrchestrationError` → `TaskerError`. When troubleshooting,
start with the most specific error type and work outward.

---

HEADER

    enum_index=0
    while [[ ${enum_index} -lt ${ENUM_COUNT} ]]; do
        enum_index=$((enum_index + 1))

        enum_file="${TMPDIR_WORK}/enum_${enum_index}.txt"
        name_file="${TMPDIR_WORK}/name_${enum_index}.txt"

        if [[ ! -f "${enum_file}" ]] || [[ ! -f "${name_file}" ]]; then
            continue
        fi

        enum_name=$(cat "${name_file}")
        variant_count=$(grep -cE '^[[:space:]]+(#\[error|[A-Z][a-z])' "${enum_file}" || echo "0")

        if [[ "${USE_OLLAMA}" == true ]]; then
            echo "  [${enum_index}/${ENUM_COUNT}] Generating guide for ${enum_name} (${variant_count} variants)..." >&2
            echo "### ${enum_name}"
            echo ""
            ollama_error_guide "${enum_name}" "${enum_file}"
        else
            deterministic_error_section "${enum_file}" "${enum_name}"
        fi

        echo ""
        echo "---"
        echo ""
    done

    if [[ "${USE_OLLAMA}" == true ]]; then
        echo "> Troubleshooting guidance generated with Ollama (\`${OLLAMA_MODEL}\`). Set \`SKIP_LLM=true\` for deterministic output."
    else
        echo "> Error messages extracted deterministically from \`#[error(...)]\` annotations."
    fi

    echo ""
    echo "---"
    echo ""
    echo "*Generated by \`generate-error-guide.sh\` from tasker-core error definitions*"

} > "${OUTPUT}"

echo "  Output: ${OUTPUT}"
echo "Error troubleshooting guide generated (${ENUM_COUNT} error enums)."
