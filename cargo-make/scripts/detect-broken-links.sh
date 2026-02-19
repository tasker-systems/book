#!/usr/bin/env bash
# =============================================================================
# Detect broken internal links in mdBook source
# =============================================================================
#
# Scans all .md files in src/ for relative markdown links and checks whether
# the target file exists on disk. Reports broken links with file, line number,
# and the link target.
#
# Ignores:
#   - External URLs (http://, https://, mailto:)
#   - Fragment-only links (#anchor)
#
# Requires: rg (ripgrep)
#
# Usage:
#   cargo make detect-broken-links
#   cargo make bl
#
# Exit codes:
#   0 - No broken links found
#   1 - One or more broken links found
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"

if ! command -v rg &>/dev/null; then
    echo "ERROR: ripgrep (rg) is required but not installed."
    exit 1
fi

TMPFILE=$(mktemp)
trap 'rm -f "${TMPFILE}"' EXIT

# ---------------------------------------------------------------------------
# Phase 1: Extract all markdown link targets with source locations
#
# rg extracts every ](target) match with file:line:match context.
# We then filter to internal links only.
# ---------------------------------------------------------------------------
rg --no-heading --line-number -o '\]\([^)]+\)' \
    --glob '*.md' --glob '!CLAUDE.md' \
    "${SRC_DIR}" \
    | sed -E 's/\]\(//; s/\)$//' \
    | sed -E 's/#.*//' \
    | sed -E 's/ ".*//' \
    | grep -v ':$' \
    | grep -v ':[[:space:]]*$' \
    | grep -v ':http' \
    | grep -v ':mailto' \
    | grep -v ':context$' \
    > "${TMPFILE}" || true

# ---------------------------------------------------------------------------
# Phase 2: Validate each link target exists on disk
# Format in TMPFILE: /path/to/file.md:linenum:target
# ---------------------------------------------------------------------------
total=0
broken=0

while IFS= read -r entry; do
    # Split file:line:target (file path may not contain colons on macOS)
    file_path="${entry%%:*}"
    rest="${entry#*:}"
    line_num="${rest%%:*}"
    target="${rest#*:}"

    # Skip empty targets
    if [[ -z "${target}" ]]; then
        continue
    fi

    total=$((total + 1))

    source_dir=$(dirname "${file_path}")
    resolved="${source_dir}/${target}"

    if [[ ! -f "${resolved}" ]] && [[ ! -d "${resolved}" ]]; then
        rel_source="${file_path#"${SRC_DIR}/"}"
        echo "  ${rel_source}:${line_num} -> ${target}"
        broken=$((broken + 1))
    fi
done < "${TMPFILE}"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Checked ${total} internal links across src/"

if [[ "${broken}" -gt 0 ]]; then
    echo "Found ${broken} broken link(s)"
    exit 1
else
    echo "No broken links found"
    exit 0
fi
