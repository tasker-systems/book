#!/usr/bin/env bash
# =============================================================================
# Sync documentation from tasker-contrib
# =============================================================================
#
# Previously synced tasker-contrib docs into src/contrib/. That section has been
# removed — contrib content is now integrated into getting-started/example-apps.md
# (book-owned). This script remains as a no-op placeholder for the cargo-make
# pipeline.
#
# Environment:
#   TASKER_CONTRIB_DIR - Path to tasker-contrib repo (default: ../tasker-contrib)
#
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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
echo "Syncing to:   (no-op — contrib content is now book-owned)"
echo ""
echo "Contrib sync complete."
