#!/usr/bin/env bash
# =============================================================================
# Generate ADR Summary Table
# =============================================================================
#
# Reads Architectural Decision Records (ADR) from tasker-core/docs/decisions/
# and generates a summary table. Optionally uses Ollama for AI-powered
# summaries of each decision.
#
# This generator is opt-in and NOT part of the default `generate` pipeline.
# Run explicitly: cargo make generate-adr-summary
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
OUTPUT="${REPO_ROOT}/src/generated/adr-summary.md"

# ---------------------------------------------------------------------------
# Source .env if present (won't override existing env vars)
# ---------------------------------------------------------------------------
if [[ -f "${REPO_ROOT}/.env" ]]; then
    while IFS= read -r line; do
        # Skip comments and empty lines
        case "${line}" in
            "#"*|"") continue ;;
        esac
        # Only set if not already in environment
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

ADR_DIR="${CORE_DIR}/docs/decisions"

# Validate source exists
if [[ ! -d "${ADR_DIR}" ]]; then
    echo "ERROR: ADR directory not found at ${ADR_DIR}"
    echo "Set TASKER_CORE_DIR to point to your tasker-core checkout."
    exit 1
fi

echo "Generating ADR summary..."
echo "  Source: ${ADR_DIR}"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# ---------------------------------------------------------------------------
# Check for Ollama availability
# ---------------------------------------------------------------------------
USE_OLLAMA=false
if [[ "${SKIP_LLM:-false}" != "true" ]] && command -v ollama &>/dev/null; then
    if curl -s --connect-timeout 2 http://localhost:11434/api/tags &>/dev/null; then
        USE_OLLAMA=true
        echo "  Ollama detected (model: ${OLLAMA_MODEL}) - using AI-powered summaries"
    else
        echo "  Ollama installed but not running - using deterministic summaries"
    fi
else
    echo "  Using deterministic summaries (Ollama not available or SKIP_LLM=true)"
fi

# ---------------------------------------------------------------------------
# Helper: Extract deterministic summary from ADR
# ---------------------------------------------------------------------------
extract_summary() {
    local file="$1"
    local in_decision=false
    local summary=""

    while IFS= read -r line; do
        if [[ "${line}" =~ ^##[[:space:]]+Decision ]] || [[ "${line}" =~ ^##[[:space:]]+decision ]]; then
            in_decision=true
            continue
        fi
        if [[ "${in_decision}" == true ]] && [[ "${line}" =~ ^## ]]; then
            break
        fi
        if [[ "${in_decision}" == true ]]; then
            local stripped
            stripped=$(echo "${line}" | sed 's/^[[:space:]]*//')
            if [[ -n "${stripped}" ]] && [[ ! "${stripped}" =~ ^--- ]]; then
                summary="${stripped}"
                break
            fi
        fi
    done < "${file}"

    if [[ ${#summary} -gt 120 ]]; then
        summary="${summary:0:117}..."
    fi

    echo "${summary}"
}

# ---------------------------------------------------------------------------
# Helper: Get Ollama summary via API
# ---------------------------------------------------------------------------
ollama_summary() {
    local file="$1"
    local title="$2"

    # Extract Context and Decision sections into a temp file
    local content_file="${TMPDIR_WORK}/content.txt"
    local in_section=false
    : > "${content_file}"

    while IFS= read -r line; do
        if [[ "${line}" =~ ^##[[:space:]]+(Context|Decision) ]]; then
            in_section=true
            continue
        fi
        if [[ "${in_section}" == true ]] && [[ "${line}" =~ ^## ]]; then
            in_section=false
            continue
        fi
        if [[ "${in_section}" == true ]]; then
            echo "${line}" >> "${content_file}"
        fi
    done < "${file}"

    # Read and truncate content
    local content
    content=$(head -c 2000 "${content_file}")

    # Build JSON payload using Python for proper escaping (avoids sed/printf fragility)
    # Falls back to a simple approach if Python is unavailable
    local payload_file="${TMPDIR_WORK}/payload.json"

    if command -v python3 &>/dev/null; then
        python3 -c "
import json, sys
prompt = 'Summarize this architectural decision record in exactly 2 sentences. Focus on what was decided and why. Title: ' + sys.argv[1] + '. Content: ' + sys.argv[2]
json.dump({'model': sys.argv[3], 'prompt': prompt, 'stream': False}, sys.stdout)
" "${title}" "${content}" "${OLLAMA_MODEL}" > "${payload_file}"
    else
        # Fallback: escape for JSON manually (handles most cases)
        local escaped_title
        local escaped_content
        escaped_title=$(echo "${title}" | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
        escaped_content=$(echo "${content}" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g; s/	/\\t/g')
        cat > "${payload_file}" <<ENDJSON
{"model":"${OLLAMA_MODEL}","prompt":"Summarize this architectural decision record in exactly 2 sentences. Focus on what was decided and why. Title: ${escaped_title}. Content: ${escaped_content}","stream":false}
ENDJSON
    fi

    # Call Ollama API
    local response_file="${TMPDIR_WORK}/response.json"
    if curl -s --max-time 60 http://localhost:11434/api/generate \
        -H "Content-Type: application/json" \
        -d "@${payload_file}" \
        -o "${response_file}" 2>/dev/null; then

        # Extract response text - handle multiline JSON response
        local summary=""
        if command -v python3 &>/dev/null; then
            summary=$(python3 -c "
import json, sys
try:
    data = json.load(open(sys.argv[1]))
    print(data.get('response', '').strip().replace('\n', ' '))
except: pass
" "${response_file}" 2>/dev/null || echo "")
        else
            # Fallback: basic sed extraction
            summary=$(sed -E 's/.*"response":"([^"]+)".*/\1/' "${response_file}" | head -1)
        fi

        if [[ -n "${summary}" ]]; then
            # Clean up: remove markdown formatting that breaks table cells
            summary=$(echo "${summary}" | tr '\n' ' ' | sed 's/|/—/g; s/  */ /g')
            if [[ ${#summary} -gt 200 ]]; then
                summary="${summary:0:197}..."
            fi
            echo "${summary}"
            return
        fi
    fi

    # Fallback to deterministic
    extract_summary "${file}"
}

# ---------------------------------------------------------------------------
# Parse ADR files
# ---------------------------------------------------------------------------
ADR_FILES=()
while IFS= read -r -d '' file; do
    ADR_FILES+=("${file}")
done < <(find "${ADR_DIR}" -name 'adr-*.md' -print0 | sort -z)

if [[ ${#ADR_FILES[@]} -eq 0 ]]; then
    echo "  No ADR files found in ${ADR_DIR}"
    exit 0
fi

# ---------------------------------------------------------------------------
# Generate output
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "${OUTPUT}")"

{
    cat <<'HEADER'
# Architectural Decision Records

> Auto-generated ADR summary. Do not edit manually.
>
> Regenerate with: `cargo make generate-adr-summary`

This page summarizes the Architectural Decision Records (ADRs) from the Tasker project.
Each ADR documents a significant design decision, its context, and consequences.

| # | Title | Status | Summary |
|---|-------|--------|---------|
HEADER

    adr_index=0
    for file in "${ADR_FILES[@]}"; do
        adr_index=$((adr_index + 1))
        filename=$(basename "${file}" .md)

        # Extract ADR number
        adr_num=$(echo "${filename}" | sed -E 's/adr-0*([0-9]+).*/\1/')

        # Extract title from first H1 or H2
        title=""
        while IFS= read -r line; do
            if [[ "${line}" =~ ^#[[:space:]]+ ]] || [[ "${line}" =~ ^##[[:space:]]+ ]]; then
                title=$(echo "${line}" | sed -E 's/^#+[[:space:]]+(ADR[- ]*[0-9]*:?[[:space:]]*)?//')
                break
            fi
        done < "${file}"

        if [[ -z "${title}" ]]; then
            title=$(echo "${filename}" | sed 's/adr-[0-9]*-//; s/-/ /g')
        fi

        # Extract status
        status="Accepted"
        while IFS= read -r line; do
            if [[ "${line}" =~ [Ss]tatus:[[:space:]]*([A-Za-z]+) ]]; then
                status="${BASH_REMATCH[1]}"
                break
            fi
        done < "${file}"

        # Get summary
        if [[ "${USE_OLLAMA}" == true ]]; then
            echo "  [${adr_index}/${#ADR_FILES[@]}] Summarizing: ${title}..." >&2
            summary=$(ollama_summary "${file}" "${title}")
        else
            summary=$(extract_summary "${file}")
        fi

        # Link to the full ADR in the decisions section
        echo "| ${adr_num} | [${title}](../decisions/${filename}.md) | ${status} | ${summary} |"
    done

    echo ""

    if [[ "${USE_OLLAMA}" == true ]]; then
        echo "> Summaries generated with Ollama (\`${OLLAMA_MODEL}\`). Set \`SKIP_LLM=true\` for deterministic summaries."
    else
        echo "> Summaries extracted deterministically from Decision sections."
    fi

    echo ""
    echo "---"
    echo ""
    echo "*Generated by \`generate-adr-summary.sh\` from tasker-core ADR files*"

} > "${OUTPUT}"

echo "  Output: ${OUTPUT}"
echo "ADR summary generated (${#ADR_FILES[@]} records)."
