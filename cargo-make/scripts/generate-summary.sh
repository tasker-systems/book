#!/usr/bin/env bash
# =============================================================================
# Generate SUMMARY.md from directory structure
# =============================================================================
#
# Scans src/ directories and generates a complete mdBook SUMMARY.md.
# Hand-written sections (getting-started, stories) use fixed structure.
# Synced sections are auto-discovered from the filesystem.
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"
SUMMARY="${SRC_DIR}/SUMMARY.md"

# ---------------------------------------------------------------------------
# Helper: Convert kebab-case filename to Title Case
# Works on macOS and Linux (no GNU sed extensions)
# ---------------------------------------------------------------------------
to_title_case() {
    echo "$1" | sed 's/-/ /g; s/_/ /g' | awk '{for(i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)}1'
}

# ---------------------------------------------------------------------------
# Helper: Generate entries for all .md files in a directory
# Sorts alphabetically, skips README.md (used as section landing page).
# ---------------------------------------------------------------------------
generate_section_entries() {
    local dir="$1"
    local rel_prefix="$2"
    local indent="$3"

    if [[ ! -d "${SRC_DIR}/${dir}" ]]; then
        return
    fi

    # Find and sort markdown files, skip README.md and CLAUDE.md
    find "${SRC_DIR}/${dir}" -maxdepth 1 -name '*.md' ! -name 'README.md' ! -name 'CLAUDE.md' -print0 \
        | sort -z \
        | while IFS= read -r -d '' file; do
            local fname
            fname=$(basename "${file}" .md)
            local rel_path="${rel_prefix}/$(basename "${file}")"
            local title
            title=$(to_title_case "${fname}")
            echo "${indent}- [${title}](${rel_path})"
        done
}

# ---------------------------------------------------------------------------
# Helper: Generate a full section with header and entries
# ---------------------------------------------------------------------------
generate_section() {
    local title="$1"
    local dir="$2"
    local readme_title="$3"

    if [[ ! -d "${SRC_DIR}/${dir}" ]]; then
        return
    fi

    # Check if there's any content
    local md_count
    md_count=$(find "${SRC_DIR}/${dir}" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')
    if [[ "${md_count}" -eq 0 ]]; then
        return
    fi

    echo ""
    echo "---"
    echo ""
    echo "# ${title}"
    echo ""

    # Section landing page (README.md)
    if [[ -f "${SRC_DIR}/${dir}/README.md" ]]; then
        echo "- [${readme_title}](${dir}/README.md)"
        # Individual pages as children
        generate_section_entries "${dir}" "${dir}" "  "
    else
        # No README - list pages as top-level entries in this section
        generate_section_entries "${dir}" "${dir}" ""
    fi
}

# ---------------------------------------------------------------------------
# Build SUMMARY.md
# ---------------------------------------------------------------------------
{
    echo "# Summary"
    echo ""
    echo "[Introduction](README.md)"
    echo "[Why Tasker?](why-tasker.md)"

    # -----------------------------------------------------------------------
    # Getting Started (Understand track) — hand-written structure
    # -----------------------------------------------------------------------
    echo ""
    echo "---"
    echo ""
    echo "# Getting Started"
    echo ""
    echo "- [Getting Started](getting-started/README.md)"
    echo "  - [Core Concepts](getting-started/concepts.md)"
    echo "  - [Handler Types](getting-started/handler-types.md)"
    echo "  - [Choosing Your Package](getting-started/choosing-your-package.md)"

    # -----------------------------------------------------------------------
    # Build Your First Project (Build track) — hand-written structure
    # -----------------------------------------------------------------------
    echo ""
    echo "---"
    echo ""
    echo "# Build Your First Project"
    echo ""
    echo "- [Build Your First Project](building/README.md)"
    echo "  - [Quick Start](building/quick-start.md)"
    echo "  - [Installation](building/install.md)"
    echo "  - [Using tasker-ctl](building/tasker-ctl.md)"
    echo "  - [Your First Handler](building/first-handler.md)"
    echo "  - [Your First Workflow](building/first-workflow.md)"
    echo "  - [Ruby](building/ruby.md)"
    echo "  - [Python](building/python.md)"
    echo "  - [TypeScript](building/typescript.md)"
    echo "  - [Rust](building/rust.md)"
    echo "  - [Next Steps](building/next-steps.md)"

    # -----------------------------------------------------------------------
    # Auto-generated sections from directory structure
    # -----------------------------------------------------------------------
    generate_section "Architecture"    "architecture"   "Architecture Overview"
    generate_section "Guides"          "guides"         "Operational Guides"
    generate_section "Workers"         "workers"        "Worker Guides"
    generate_section "Observability"   "observability"  "Observability"
    generate_section "Principles"      "principles"     "Design Principles"
    generate_section "Vision"          "vision"         "Vision"
    generate_section "Reference"       "reference"      "Reference"

    # Generated reference docs (diagrams, config, schema) as its own section
    if [[ -d "${SRC_DIR}/generated" ]]; then
        gen_count=$(find "${SRC_DIR}/generated" -maxdepth 1 -name '*.md' ! -name 'CLAUDE.md' | wc -l | tr -d ' ')
        if [[ "${gen_count}" -gt 0 ]]; then
            echo ""
            echo "---"
            echo ""
            echo "# Generated Reference"
            echo ""
            if [[ -f "${SRC_DIR}/generated/index.md" ]]; then
                echo "- [Generated Reference](generated/index.md)"
            fi
            # Skip index.md too (already used as landing page)
            find "${SRC_DIR}/generated" -maxdepth 1 -name '*.md' \
                ! -name 'README.md' ! -name 'CLAUDE.md' ! -name 'index.md' -print0 \
                | sort -z \
                | while IFS= read -r -d '' file; do
                    fname=$(basename "${file}" .md)
                    title=$(to_title_case "${fname}")
                    echo "  - [${title}](generated/$(basename "${file}"))"
                done
        fi
    fi

    generate_section "Auth"            "auth"           "Authentication & Authorization"
    generate_section "Operations"      "operations"     "Operations"
    generate_section "Testing"         "testing"        "Testing"
    generate_section "Security"        "security"       "Security"
    generate_section "Decisions"       "decisions"      "Architectural Decisions"
    generate_section "Benchmarks"      "benchmarks"     "Benchmarks"

    # -----------------------------------------------------------------------
    # Contrib
    # -----------------------------------------------------------------------
    if [[ -d "${SRC_DIR}/contrib" ]]; then
        echo ""
        echo "---"
        echo ""
        echo "# Contrib"
        echo ""
        if [[ -f "${SRC_DIR}/contrib/README.md" ]]; then
            echo "- [Framework Integrations](contrib/README.md)"
        fi
        if [[ -f "${SRC_DIR}/contrib/example-apps.md" ]]; then
            echo "  - [Example Apps](contrib/example-apps.md)"
        fi

        if [[ -d "${SRC_DIR}/contrib/examples" ]]; then
            if [[ -f "${SRC_DIR}/contrib/examples/README.md" ]]; then
                echo "  - [Examples](contrib/examples/README.md)"
            fi
            for example_dir in "${SRC_DIR}/contrib/examples"/*/; do
                if [[ -f "${example_dir}/README.md" ]]; then
                    dirname=$(basename "${example_dir}")
                    title=$(to_title_case "${dirname}")
                    echo "    - [${title}](contrib/examples/${dirname}/README.md)"
                fi
            done
        fi
    fi

    # -----------------------------------------------------------------------
    # Stories (hand-written blog series)
    # -----------------------------------------------------------------------
    generate_section "Stories"          "stories"        "Engineering Stories"

} > "${SUMMARY}"

echo "Generated ${SUMMARY}"
entry_count=$(grep -c '^\s*-' "${SUMMARY}" || true)
echo "  ${entry_count} entries in table of contents"
