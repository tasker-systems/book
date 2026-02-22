#!/usr/bin/env bash
# =============================================================================
# Sync documentation from tasker-core/docs into src/
# =============================================================================
#
# Copies selected directories from tasker-core/docs into the mdBook source
# directory. Skips internal-only content (ticket-specs, development).
#
# Environment:
#   TASKER_CORE_DIR - Path to tasker-core repo (default: ../tasker-core)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SRC_DIR="${REPO_ROOT}/src"

CORE_DIR="${TASKER_CORE_DIR:-../tasker-core}"
CORE_DOCS="${CORE_DIR}/docs"

# Resolve relative path from repo root
if [[ ! "${CORE_DIR}" = /* ]]; then
    CORE_DIR="${REPO_ROOT}/${CORE_DIR}"
    CORE_DOCS="${CORE_DIR}/docs"
fi

# Validate source exists
if [[ ! -d "${CORE_DOCS}" ]]; then
    echo "ERROR: tasker-core docs not found at ${CORE_DOCS}"
    echo "Set TASKER_CORE_DIR to point to your tasker-core checkout."
    exit 1
fi

echo "Syncing from: ${CORE_DOCS}"
echo "Syncing to:   ${SRC_DIR}"
echo ""

# ---------------------------------------------------------------------------
# Directories to sync (tasker-core/docs/{dir} -> src/{dir})
# ---------------------------------------------------------------------------
SYNC_DIRS=(
    "architecture"
    "auth"
    "benchmarks"
    "decisions"
    "generated"
    "guides"
    "observability"
    "principles"
    "reference"
    "security"
    "testing"
    "workers"
)

# Directories to SKIP (internal-only)
# - ticket-specs: Linear ticket specifications (176 files, internal planning)
# - development: Contributor best practices (internal to core development)
SKIP_DIRS=(
    "ticket-specs"
    "development"
)

# ---------------------------------------------------------------------------
# Files to preserve in generated/ (locally-generated content)
# These are created by local scripts, not synced from tasker-core
# ---------------------------------------------------------------------------
LOCAL_GENERATED_FILES=(
    "adr-summary.md"
    "config-operational-guide.md"
    "crate-dependency-graph.md"
    "database-schema.md"
    "error-troubleshooting-guide.md"
    "state-machine-diagrams.md"
)

# ---------------------------------------------------------------------------
# Files to preserve in reference/ (book-owned content)
# These are authored in tasker-book, not synced from tasker-core
# ---------------------------------------------------------------------------
LOCAL_REFERENCE_FILES=(
    "class-based-handlers.md"
)

# ---------------------------------------------------------------------------
# Sync directories
# ---------------------------------------------------------------------------
for dir in "${SYNC_DIRS[@]}"; do
    src="${CORE_DOCS}/${dir}"
    dest="${SRC_DIR}/${dir}"

    if [[ -d "${src}" ]]; then
        mkdir -p "${dest}"

        # Build rsync exclude args
        RSYNC_EXCLUDES=(
            --exclude='.DS_Store'
            --exclude='CLAUDE.md'
        )

        # For generated/, also preserve locally-generated files
        if [[ "${dir}" == "generated" ]]; then
            for file in "${LOCAL_GENERATED_FILES[@]}"; do
                RSYNC_EXCLUDES+=(--exclude="${file}")
            done
        fi

        # For reference/, also preserve book-owned files
        if [[ "${dir}" == "reference" ]]; then
            for file in "${LOCAL_REFERENCE_FILES[@]}"; do
                RSYNC_EXCLUDES+=(--exclude="${file}")
            done
        fi

        rsync -a --delete "${RSYNC_EXCLUDES[@]}" "${src}/" "${dest}/"
        count=$(find "${dest}" -name '*.md' | wc -l | tr -d ' ')
        echo "  ${dir}/ -> ${count} files"
    else
        echo "  ${dir}/ -> SKIP (not found in source)"
    fi
done

# ---------------------------------------------------------------------------
# Sync top-level docs files
# ---------------------------------------------------------------------------
# why-tasker.md is useful for the overview page
for file in "why-tasker.md"; do
    src="${CORE_DOCS}/${file}"
    if [[ -f "${src}" ]]; then
        cp "${src}" "${SRC_DIR}/${file}"
        echo "  ${file} -> copied"
    fi
done

# ---------------------------------------------------------------------------
# Post-sync cleanup: remove any files that shouldn't be published
# ---------------------------------------------------------------------------
find "${SRC_DIR}" -name 'CLAUDE.md' -not -path "${SRC_DIR}/CLAUDE.md" -type f -delete 2>/dev/null || true

# ---------------------------------------------------------------------------
# Post-sync: fix cross-directory link patterns
# ---------------------------------------------------------------------------
bash "${SCRIPT_DIR}/fixup-synced-links.sh" "${SRC_DIR}"

# ---------------------------------------------------------------------------
# Post-sync: auto-fix markdown formatting on synced content
# ---------------------------------------------------------------------------
if command -v npx &>/dev/null; then
    echo ""
    echo "Auto-fixing markdown formatting..."
    npx markdownlint-cli2 --fix "${SRC_DIR}/**/*.md" 2>/dev/null || true
fi

echo ""
echo "Core docs sync complete."
