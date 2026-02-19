#!/usr/bin/env bash
# =============================================================================
# Sync documentation from tasker-contrib into src/contrib/
# =============================================================================
#
# Copies documentation and examples from tasker-contrib into the mdBook source
# directory under src/contrib/.
#
# Environment:
#   TASKER_CONTRIB_DIR - Path to tasker-contrib repo (default: ../tasker-contrib)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"

CONTRIB_DIR="${TASKER_CONTRIB_DIR:-../tasker-contrib}"

# Resolve relative path from repo root
if [[ ! "${CONTRIB_DIR}" = /* ]]; then
    CONTRIB_DIR="${REPO_ROOT}/${CONTRIB_DIR}"
fi

# Validate source exists
if [[ ! -d "${CONTRIB_DIR}" ]]; then
    echo "WARNING: tasker-contrib not found at ${CONTRIB_DIR}"
    echo "Set TASKER_CONTRIB_DIR to point to your tasker-contrib checkout."
    echo "Skipping contrib sync."
    exit 0
fi

echo "Syncing from: ${CONTRIB_DIR}"
echo "Syncing to:   ${SRC_DIR}/contrib"
echo ""

DEST="${SRC_DIR}/contrib"
mkdir -p "${DEST}"

# ---------------------------------------------------------------------------
# contrib/README.md is book-owned (consumer-facing landing page)
# Skip syncing to avoid overwriting with internal planning doc
# ---------------------------------------------------------------------------
echo "  README.md -> skipped (book-owned)"

# ---------------------------------------------------------------------------
# Sync contrib-specific docs (skip ticket-specs)
# ---------------------------------------------------------------------------
for dir in "architecture" "guides"; do
    src="${CONTRIB_DIR}/docs/${dir}"
    if [[ -d "${src}" ]] && [[ -n "$(ls -A "${src}" 2>/dev/null)" ]]; then
        mkdir -p "${DEST}/${dir}"
        rsync -a --delete \
            --exclude='.DS_Store' \
            "${src}/" "${DEST}/${dir}/"
        count=$(find "${DEST}/${dir}" -name '*.md' | wc -l | tr -d ' ')
        echo "  docs/${dir}/ -> ${count} files"
    fi
done

echo ""
echo "Contrib sync complete."
