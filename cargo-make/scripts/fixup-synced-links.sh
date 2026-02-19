#!/usr/bin/env bash
# =============================================================================
# Fix broken internal links in synced documentation
# =============================================================================
#
# After rsync from tasker-core/docs, some relative links don't resolve because
# tasker-core/docs and tasker-book/src have slightly different structure
# assumptions. This script rewrites known broken patterns.
#
# Called automatically by sync-core.sh after rsync completes.
#
# Categories of fixes:
#   1. Cross-section sibling refs missing "../" prefix
#      e.g. in guides/: "crate-architecture.md" -> "../architecture/crate-architecture.md"
#   2. Parent-relative refs missing section directory
#      e.g. in workers/: "../worker-event-systems.md" -> "../architecture/worker-event-systems.md"
#   3. Renamed directories
#      e.g. "../worker-crates/" -> "../workers/"
#   4. Sub-section refs that need "../" instead of direct child path
#      e.g. in architecture/: "observability/README.md" -> "../observability/README.md"
#   5. Links to excluded/non-existent content -> removed entirely
#
# =============================================================================

set -euo pipefail

SRC_DIR="${1:?Usage: fixup-synced-links.sh <src-dir>}"

if [[ ! -d "${SRC_DIR}" ]]; then
    echo "ERROR: Source directory not found: ${SRC_DIR}"
    exit 1
fi

fixed=0

# ---------------------------------------------------------------------------
# Helper: sed in-place (macOS-compatible)
# ---------------------------------------------------------------------------
sed_i() {
    sed -i '' "$@"
}

# ---------------------------------------------------------------------------
# Helper: Apply a sed replacement to files matching a glob, count changes
# Args: directory glob_pattern sed_expression description
# ---------------------------------------------------------------------------
fixup() {
    local dir="$1"
    local pattern="$2"
    local sed_expr="$3"
    local desc="$4"
    local target="${SRC_DIR}/${dir}"

    if [[ ! -d "${target}" ]]; then
        return
    fi

    local count=0
    while IFS= read -r -d '' file; do
        if grep -q "${pattern}" "${file}" 2>/dev/null; then
            sed_i "s|${pattern}|${sed_expr}|g" "${file}"
            count=$((count + 1))
        fi
    done < <(find "${target}" -name '*.md' -print0)

    if [[ ${count} -gt 0 ]]; then
        fixed=$((fixed + count))
        echo "  ${desc} (${count} files)"
    fi
}

# ---------------------------------------------------------------------------
# Helper: Apply a sed replacement to a single file
# Args: file_path pattern replacement description
# ---------------------------------------------------------------------------
fixup_file() {
    local file="${SRC_DIR}/$1"
    local pattern="$2"
    local replacement="$3"
    local desc="$4"

    if [[ -f "${file}" ]] && grep -q "${pattern}" "${file}" 2>/dev/null; then
        sed_i "s|${pattern}|${replacement}|g" "${file}"
        fixed=$((fixed + 1))
        echo "  ${desc}"
    fi
}

echo "Fixing synced link patterns..."

# =========================================================================
# 1. From workers/: parent-relative links to architecture files
#    ../worker-event-systems.md -> ../architecture/worker-event-systems.md
#    ../worker-actors.md -> ../architecture/worker-actors.md
#    ../events-and-commands.md -> ../architecture/events-and-commands.md
# =========================================================================
fixup "workers" \
    '](../worker-event-systems.md' \
    '](../architecture/worker-event-systems.md' \
    "workers/: ../worker-event-systems.md -> ../architecture/"

fixup "workers" \
    '](../worker-actors.md' \
    '](../architecture/worker-actors.md' \
    "workers/: ../worker-actors.md -> ../architecture/"

fixup "workers" \
    '](../events-and-commands.md' \
    '](../architecture/events-and-commands.md' \
    "workers/: ../events-and-commands.md -> ../architecture/"

# =========================================================================
# 2. From operations/: parent-relative links to architecture files
#    ../backpressure-architecture.md -> ../architecture/backpressure-architecture.md
#    ../circuit-breakers.md -> ../architecture/circuit-breakers.md
#    ../worker-event-systems.md -> ../architecture/worker-event-systems.md
# =========================================================================
fixup "operations" \
    '](../backpressure-architecture.md' \
    '](../architecture/backpressure-architecture.md' \
    "operations/: ../backpressure-architecture.md -> ../architecture/"

fixup "operations" \
    '](../circuit-breakers.md' \
    '](../architecture/circuit-breakers.md' \
    "operations/: ../circuit-breakers.md -> ../architecture/"

fixup "operations" \
    '](../worker-event-systems.md' \
    '](../architecture/worker-event-systems.md' \
    "operations/: ../worker-event-systems.md -> ../architecture/"

fixup "operations" \
    '](../development/mpsc-channel-guidelines.md' \
    '](../architecture/backpressure-architecture.md' \
    "operations/: ../development/mpsc-channel-guidelines.md -> ../architecture/backpressure-architecture.md"

# =========================================================================
# 3. From observability/: parent-relative links to architecture files
#    ../domain-events.md -> ../architecture/domain-events.md
#    ../backpressure-architecture.md -> ../architecture/backpressure-architecture.md
#    ../circuit-breakers.md -> ../architecture/circuit-breakers.md
#    ../deployment-patterns.md -> ../architecture/deployment-patterns.md
#    ../task-and-step-readiness-and-execution.md -> ../reference/task-and-step-readiness-and-execution.md
# =========================================================================
fixup "observability" \
    '](../domain-events.md' \
    '](../architecture/domain-events.md' \
    "observability/: ../domain-events.md -> ../architecture/"

fixup "observability" \
    '](../backpressure-architecture.md' \
    '](../architecture/backpressure-architecture.md' \
    "observability/: ../backpressure-architecture.md -> ../architecture/"

fixup "observability" \
    '](../circuit-breakers.md' \
    '](../architecture/circuit-breakers.md' \
    "observability/: ../circuit-breakers.md -> ../architecture/"

fixup "observability" \
    '](../deployment-patterns.md' \
    '](../architecture/deployment-patterns.md' \
    "observability/: ../deployment-patterns.md -> ../architecture/"

fixup "observability" \
    '](../task-and-step-readiness-and-execution.md' \
    '](../reference/task-and-step-readiness-and-execution.md' \
    "observability/: ../task-and-step-readiness-and-execution.md -> ../reference/"

# =========================================================================
# 4. From guides/: bare filename links to architecture files
#    These files are in guides/ but link as if architecture/ files are siblings
# =========================================================================
for arch_file in crate-architecture.md states-and-lifecycles.md events-and-commands.md \
                 deployment-patterns.md; do
    fixup "guides" \
        "](${arch_file}" \
        "](../architecture/${arch_file}" \
        "guides/: ${arch_file} -> ../architecture/${arch_file}"
done

# task-and-step-readiness-and-execution.md lives in reference/, not architecture/
fixup "guides" \
    '](task-and-step-readiness-and-execution.md' \
    '](../reference/task-and-step-readiness-and-execution.md' \
    "guides/: task-and-step-readiness-and-execution.md -> ../reference/"

# Also fix bare observability/README.md and benchmarks/README.md refs from guides/
fixup "guides" \
    '](observability/README.md' \
    '](../observability/README.md' \
    "guides/: observability/README.md -> ../observability/README.md"

fixup "guides" \
    '](benchmarks/README.md' \
    '](../benchmarks/README.md' \
    "guides/: benchmarks/README.md -> ../benchmarks/README.md"

# =========================================================================
# 5. From architecture/: sub-paths that should be sibling-relative
#    observability/README.md -> ../observability/README.md
#    operations/... -> ../operations/...
#    development/... -> removed (not synced)
#    quick-start.md -> ../guides/quick-start.md
#    task-and-step-readiness-and-execution.md -> ../reference/task-and-step-readiness-and-execution.md
#    configuration-management.md -> ../guides/configuration-management.md
# =========================================================================
fixup "architecture" \
    '](observability/README.md' \
    '](../observability/README.md' \
    "architecture/: observability/README.md -> ../observability/"

fixup "architecture" \
    '](operations/backpressure-monitoring.md' \
    '](../operations/backpressure-monitoring.md' \
    "architecture/: operations/backpressure-monitoring.md -> ../operations/"

fixup "architecture" \
    '](operations/mpsc-channel-tuning.md' \
    '](../operations/mpsc-channel-tuning.md' \
    "architecture/: operations/mpsc-channel-tuning.md -> ../operations/"

fixup "architecture" \
    '](quick-start.md' \
    '](../guides/quick-start.md' \
    "architecture/: quick-start.md -> ../guides/quick-start.md"

fixup "architecture" \
    '](task-and-step-readiness-and-execution.md' \
    '](../reference/task-and-step-readiness-and-execution.md' \
    "architecture/: task-and-step-readiness-and-execution.md -> ../reference/"

fixup "architecture" \
    '](configuration-management.md' \
    '](../guides/configuration-management.md' \
    "architecture/: configuration-management.md -> ../guides/"

# =========================================================================
# 6. From principles/: worker-crates -> workers (directory renamed)
# =========================================================================
fixup "principles" \
    '](../worker-crates/' \
    '](../workers/' \
    "principles/: ../worker-crates/ -> ../workers/"

# Also fix parent-relative links to architecture files from principles/
fixup "principles" \
    '](../idempotency-and-atomicity.md' \
    '](../architecture/idempotency-and-atomicity.md' \
    "principles/: ../idempotency-and-atomicity.md -> ../architecture/"

fixup "principles" \
    '](../states-and-lifecycles.md' \
    '](../architecture/states-and-lifecycles.md' \
    "principles/: ../states-and-lifecycles.md -> ../architecture/"

# =========================================================================
# 7. From decisions/: parent-relative links
# =========================================================================
fixup "decisions" \
    '](../task-and-step-readiness-and-execution.md' \
    '](../reference/task-and-step-readiness-and-execution.md' \
    "decisions/: ../task-and-step-readiness-and-execution.md -> ../reference/"

fixup "decisions" \
    '](../states-and-lifecycles.md' \
    '](../architecture/states-and-lifecycles.md' \
    "decisions/: ../states-and-lifecycles.md -> ../architecture/"

fixup "decisions" \
    '](../development/ffi-callback-safety.md' \
    '](../workers/ffi-safety.md' \
    "decisions/: ../development/ffi-callback-safety.md -> ../workers/ffi-safety.md"

# =========================================================================
# 8. From reference/: links to sibling sections
# =========================================================================
fixup "reference" \
    '](./states-and-lifecycles.md' \
    '](../architecture/states-and-lifecycles.md' \
    "reference/: ./states-and-lifecycles.md -> ../architecture/"

fixup "reference" \
    '](./observability/README.md' \
    '](../observability/README.md' \
    "reference/: ./observability/README.md -> ../observability/"

fixup "reference" \
    '](./configuration-management.md' \
    '](../guides/configuration-management.md' \
    "reference/: ./configuration-management.md -> ../guides/"

fixup "reference" \
    '](./deployment-patterns.md' \
    '](../architecture/deployment-patterns.md' \
    "reference/: ./deployment-patterns.md -> ../architecture/"

fixup "reference" \
    '](events-and-commands.md' \
    '](../architecture/events-and-commands.md' \
    "reference/: events-and-commands.md -> ../architecture/"

fixup "reference" \
    '](states-and-lifecycles.md' \
    '](../architecture/states-and-lifecycles.md' \
    "reference/: states-and-lifecycles.md -> ../architecture/"

fixup "reference" \
    '](../development/' \
    '](../workers/' \
    "reference/: ../development/ -> ../workers/"

# =========================================================================
# 9. From architecture/: links to development/ (excluded from sync)
#    Map to closest equivalent in the book
# =========================================================================
fixup "architecture" \
    '](development/mpsc-channel-guidelines.md' \
    '](backpressure-architecture.md' \
    "architecture/: development/mpsc-channel-guidelines.md -> backpressure-architecture.md"

fixup "architecture" \
    '](development/ffi-callback-safety.md' \
    '](../workers/ffi-safety.md' \
    "architecture/: development/ffi-callback-safety.md -> ../workers/ffi-safety.md"

# =========================================================================
# 10. From workers/: links to development/ (excluded from sync)
# =========================================================================
fixup "workers" \
    '](../development/ffi-callback-safety.md' \
    '](ffi-safety.md' \
    "workers/: ../development/ffi-callback-safety.md -> ffi-safety.md"

fixup "workers" \
    '](../development/mpsc-channel-guidelines.md' \
    '](../architecture/backpressure-architecture.md' \
    "workers/: ../development/mpsc-channel-guidelines.md -> ../architecture/backpressure-architecture.md"

# =========================================================================
# 11. From testing/: links to development/ (excluded from sync)
# =========================================================================
fixup "testing" \
    '](../development/tooling.md' \
    '](../CONTRIBUTING.md' \
    "testing/: ../development/tooling.md -> ../CONTRIBUTING.md"

# =========================================================================
# 12. Specific file fixes for links to non-existent content
#     Remove or redirect links that point to files never synced/created
# =========================================================================

# architecture/README.md: ../CHRONOLOGY.md doesn't exist
fixup_file "architecture/README.md" \
    '](../CHRONOLOGY.md)' \
    '](../why-tasker.md)' \
    "architecture/README.md: ../CHRONOLOGY.md -> ../why-tasker.md"

# why-tasker.md: CHRONOLOGY.md doesn't exist
fixup_file "why-tasker.md" \
    '](CHRONOLOGY.md)' \
    '](why-tasker.md)' \
    "why-tasker.md: CHRONOLOGY.md -> self-link removed"

# architecture/crate-architecture.md: archive/ruby-integration-lessons.md doesn't exist
fixup_file "architecture/crate-architecture.md" \
    '](archive/ruby-integration-lessons.md)' \
    '](../workers/ruby.md)' \
    "architecture/crate-architecture.md: archive link -> ../workers/ruby.md"

# =========================================================================
# 13. From benchmarks/: parent-relative links to architecture
# =========================================================================
fixup "benchmarks" \
    '](../deployment-patterns.md' \
    '](../architecture/deployment-patterns.md' \
    "benchmarks/: ../deployment-patterns.md -> ../architecture/"

# =========================================================================
# 14. From architecture/: bare benchmarks/ ref needs ../
# =========================================================================
fixup "architecture" \
    '](benchmarks/README.md' \
    '](../benchmarks/README.md' \
    "architecture/: benchmarks/README.md -> ../benchmarks/"

# =========================================================================
# 15. From guides/: testing/ ref needs ../
# =========================================================================
fixup "guides" \
    '](testing/' \
    '](../testing/' \
    "guides/: testing/ -> ../testing/"

# Also fix bug-reports/ links (not synced) -> redirect to retry-semantics itself
fixup "guides" \
    '](bug-reports/2025-10-05-retry-eligibility-bug.md' \
    '](../decisions/adr-004-backoff-consolidation.md' \
    "guides/: bug-reports/ -> ../decisions/adr-004-backoff-consolidation.md"

# environment-configuration-comparison.md doesn't exist -> redirect to configuration-management
fixup "guides" \
    '](environment-configuration-comparison.md' \
    '](configuration-management.md' \
    "guides/: environment-configuration-comparison.md -> configuration-management.md"

# =========================================================================
# 16. Source code links -> GitHub URLs
#     Files that reference Rust source, SQL migrations, or config files
#     should link to the tasker-core GitHub repository
# =========================================================================
GITHUB_BASE="https://github.com/tasker-systems/tasker-core/blob/main"

# ../../tasker-orchestration/src/... -> GitHub
fixup "decisions" \
    '](../../tasker-orchestration/' \
    "](${GITHUB_BASE}/tasker-orchestration/" \
    "decisions/: source code links -> GitHub"

# ../../migrations/... -> GitHub
fixup "decisions" \
    '](../../migrations/' \
    "](${GITHUB_BASE}/migrations/" \
    "decisions/: migration links -> GitHub"

# ../../config/... -> GitHub (from auth/)
fixup "auth" \
    '](../../config/' \
    "](${GITHUB_BASE}/config/" \
    "auth/: config links -> GitHub"

# =========================================================================
# 17. Non-existent observability files -> remove broken link targets
# =========================================================================

# sql-benchmarks.md never existed in book
fixup_file "observability/README.md" \
    '](../benchmarks/sql-benchmarks.md)' \
    '](../benchmarks/README.md)' \
    "observability/README.md: sql-benchmarks.md -> benchmarks/README.md"

# VERIFICATION_RESULTS.md never existed
fixup_file "observability/README.md" \
    '](./VERIFICATION_RESULTS.md)' \
    '](metrics-verification.md)' \
    "observability/README.md: VERIFICATION_RESULTS.md -> metrics-verification.md"

# phase-5.4-distributed-benchmarks-plan.md never existed
fixup "observability" \
    '](./phase-5.4-distributed-benchmarks-plan.md' \
    '](benchmark-strategy-summary.md' \
    "observability/: phase-5.4 plan -> benchmark-strategy-summary.md"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
if [[ ${fixed} -gt 0 ]]; then
    echo "Fixed links in ${fixed} file(s)."
else
    echo "No link fixups needed."
fi
