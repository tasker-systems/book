#!/usr/bin/env bash
# =============================================================================
# Generate Crate Dependency Graph (Mermaid)
# =============================================================================
#
# Parses Cargo.toml files in the tasker-core workspace to extract path
# dependencies between crates, then generates a Mermaid flowchart showing
# the inter-crate dependency structure.
#
# Environment:
#   TASKER_CORE_DIR - Path to tasker-core repo (default: ../tasker-core)
#
# Compatible with macOS bash 3.2 (no associative arrays or GNU extensions).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT="${REPO_ROOT}/src/generated/crate-dependency-graph.md"

CORE_DIR="${TASKER_CORE_DIR:-../tasker-core}"

# Resolve relative path from repo root
if [[ ! "${CORE_DIR}" = /* ]]; then
    CORE_DIR="${REPO_ROOT}/${CORE_DIR}"
fi

# Validate source exists
if [[ ! -f "${CORE_DIR}/Cargo.toml" ]]; then
    echo "ERROR: tasker-core not found at ${CORE_DIR}"
    echo "Set TASKER_CORE_DIR to point to your tasker-core checkout."
    exit 1
fi

echo "Generating crate dependency graph..."
echo "  Source: ${CORE_DIR}"

# Use temp files for data (bash 3.2 compatible approach instead of assoc arrays)
TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# ---------------------------------------------------------------------------
# Parse workspace members from root Cargo.toml
# ---------------------------------------------------------------------------
MEMBERS=()
in_members=false
while IFS= read -r line; do
    line="${line%%#*}"
    if [[ "${line}" =~ members[[:space:]]*= ]]; then
        in_members=true
        continue
    fi
    if [[ "${in_members}" == true ]]; then
        if [[ "${line}" =~ \] ]]; then
            break
        fi
        if [[ "${line}" =~ \"([^\"]+)\" ]]; then
            member="${BASH_REMATCH[1]}"
            if [[ "${member}" != "." ]]; then
                MEMBERS+=("${member}")
            fi
        fi
    fi
done < "${CORE_DIR}/Cargo.toml"

# ---------------------------------------------------------------------------
# For each member, extract crate name and path dependencies
# Store in temp files: ${TMPDIR_WORK}/name_${index} and ${TMPDIR_WORK}/deps_${index}
# ---------------------------------------------------------------------------
for i in "${!MEMBERS[@]}"; do
    member="${MEMBERS[$i]}"
    cargo_toml="${CORE_DIR}/${member}/Cargo.toml"
    if [[ ! -f "${cargo_toml}" ]]; then
        echo "unknown-${i}" > "${TMPDIR_WORK}/name_${i}"
        echo "" > "${TMPDIR_WORK}/deps_${i}"
        continue
    fi

    # Extract crate name from [package] section
    crate_name=""
    in_package=false
    while IFS= read -r line; do
        line="${line%%#*}"
        if [[ "${line}" =~ ^\[package\] ]]; then
            in_package=true
            continue
        fi
        if [[ "${line}" =~ ^\[ ]] && [[ "${in_package}" == true ]]; then
            break
        fi
        if [[ "${in_package}" == true ]] && [[ "${line}" =~ ^name[[:space:]]*=[[:space:]]*\"([^\"]+)\" ]]; then
            crate_name="${BASH_REMATCH[1]}"
            break
        fi
    done < "${cargo_toml}"

    if [[ -z "${crate_name}" ]]; then
        crate_name=$(basename "${member}")
    fi

    echo "${crate_name}" > "${TMPDIR_WORK}/name_${i}"

    # Extract path dependencies from [dependencies] section (skip dev/build deps)
    deps=""
    in_deps=false
    while IFS= read -r line; do
        line="${line%%#*}"
        if [[ "${line}" =~ ^\[dependencies\] ]]; then
            in_deps=true
            continue
        fi
        if [[ "${line}" =~ ^\[ ]]; then
            in_deps=false
            continue
        fi
        if [[ "${in_deps}" == true ]] && [[ "${line}" =~ path[[:space:]]*= ]]; then
            dep_key=$(echo "${line}" | sed -E 's/^([a-zA-Z0-9_-]+).*/\1/' | tr -d ' ')
            if [[ -n "${dep_key}" ]]; then
                deps="${deps} ${dep_key}"
            fi
        fi
    done < "${cargo_toml}"

    echo "${deps}" > "${TMPDIR_WORK}/deps_${i}"
done

# ---------------------------------------------------------------------------
# Helper: get crate name by index
# ---------------------------------------------------------------------------
get_name() {
    cat "${TMPDIR_WORK}/name_${1}"
}

get_deps() {
    cat "${TMPDIR_WORK}/deps_${1}"
}

# Helper: check if a dep name is a workspace crate
is_workspace_crate() {
    local dep_name="$1"
    for j in "${!MEMBERS[@]}"; do
        local cname
        cname=$(get_name "$j")
        if [[ "${cname}" == "${dep_name}" ]]; then
            return 0
        fi
    done
    return 1
}

# ---------------------------------------------------------------------------
# Classify crates into subgraphs
# ---------------------------------------------------------------------------
CORE_LIBS=()
SERVICES=()
FFI_WORKERS=()

for i in "${!MEMBERS[@]}"; do
    member="${MEMBERS[$i]}"
    name=$(get_name "$i")
    case "${member}" in
        workers/*)
            FFI_WORKERS+=("${name}")
            ;;
        tasker-shared|tasker-pgmq)
            CORE_LIBS+=("${name}")
            ;;
        *)
            SERVICES+=("${name}")
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Generate Mermaid diagram
# ---------------------------------------------------------------------------
node_id() {
    echo "$1" | tr '-' '_'
}

mkdir -p "$(dirname "${OUTPUT}")"

{
    cat <<'HEADER'
# Crate Dependency Graph

> Auto-generated from `Cargo.toml` workspace analysis. Do not edit manually.
>
> Regenerate with: `cargo make generate-crate-deps`

This diagram shows the inter-crate dependency structure of the tasker-core workspace.
Arrows point from dependent to dependency (A → B means "A depends on B").

```mermaid
graph TD
HEADER

    # Subgraph: Core Libraries
    echo "    subgraph core[\"Core Libraries\"]"
    for name in "${CORE_LIBS[@]}"; do
        echo "        $(node_id "${name}")[\"${name}\"]"
    done
    echo "    end"
    echo ""

    # Subgraph: Services
    echo "    subgraph services[\"Services\"]"
    for name in "${SERVICES[@]}"; do
        echo "        $(node_id "${name}")[\"${name}\"]"
    done
    echo "    end"
    echo ""

    # Subgraph: FFI Workers
    if [[ ${#FFI_WORKERS[@]} -gt 0 ]]; then
        echo "    subgraph workers[\"FFI Workers\"]"
        for name in "${FFI_WORKERS[@]}"; do
            echo "        $(node_id "${name}")[\"${name}\"]"
        done
        echo "    end"
        echo ""
    fi

    # Edges
    for i in "${!MEMBERS[@]}"; do
        name=$(get_name "$i")
        deps=$(get_deps "$i")
        for dep in ${deps}; do
            if is_workspace_crate "${dep}"; then
                echo "    $(node_id "${name}") --> $(node_id "${dep}")"
            fi
        done
    done

    echo ""

    # Styling
    cat <<'STYLE'
    classDef coreLib fill:#e1f5fe,stroke:#0288d1,stroke-width:2px
    classDef service fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    classDef worker fill:#e8f5e9,stroke:#388e3c,stroke-width:2px
STYLE

    # Apply styles
    if [[ ${#CORE_LIBS[@]} -gt 0 ]]; then
        nodes=""
        for name in "${CORE_LIBS[@]}"; do
            nodes="${nodes},$(node_id "${name}")"
        done
        echo "    class ${nodes#,} coreLib"
    fi

    if [[ ${#SERVICES[@]} -gt 0 ]]; then
        nodes=""
        for name in "${SERVICES[@]}"; do
            nodes="${nodes},$(node_id "${name}")"
        done
        echo "    class ${nodes#,} service"
    fi

    if [[ ${#FFI_WORKERS[@]} -gt 0 ]]; then
        nodes=""
        for name in "${FFI_WORKERS[@]}"; do
            nodes="${nodes},$(node_id "${name}")"
        done
        echo "    class ${nodes#,} worker"
    fi

    echo '```'
    echo ""

    # Summary table
    echo "## Workspace Crates"
    echo ""
    echo "| Crate | Category | Dependencies |"
    echo "|-------|----------|-------------|"
    for i in "${!MEMBERS[@]}"; do
        member="${MEMBERS[$i]}"
        name=$(get_name "$i")
        deps=$(get_deps "$i")
        # Determine category
        case "${member}" in
            workers/*) category="FFI Worker" ;;
            tasker-shared|tasker-pgmq) category="Core Library" ;;
            *) category="Service" ;;
        esac
        # Format deps
        dep_trimmed=$(echo "${deps}" | tr -d ' ' | tr -s ' ')
        if [[ -z "${dep_trimmed}" ]]; then
            dep_str="*(none)*"
        else
            dep_str=""
            for dep in ${deps}; do
                dep_str="${dep_str}, \`${dep}\`"
            done
            dep_str="${dep_str#, }"
        fi
        echo "| \`${name}\` | ${category} | ${dep_str} |"
    done
    echo ""
    echo "---"
    echo ""
    echo "*Generated by \`generate-crate-deps.sh\` from tasker-core workspace analysis*"

} > "${OUTPUT}"

echo "  Output: ${OUTPUT}"
echo "Crate dependency graph generated (${#MEMBERS[@]} crates)."
