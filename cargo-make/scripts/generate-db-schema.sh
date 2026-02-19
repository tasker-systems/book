#!/usr/bin/env bash
# =============================================================================
# Generate Database Schema ER Diagram (Mermaid)
# =============================================================================
#
# Parses SQL migration files from tasker-core to extract table definitions
# and foreign key relationships, then generates a Mermaid erDiagram.
#
# Source files:
#   migrations/20260110000001_schema_and_tables.sql
#   migrations/20260110000002_constraints_and_indexes.sql
#
# Environment:
#   TASKER_CORE_DIR - Path to tasker-core repo (default: ../tasker-core)
#
# Compatible with macOS bash 3.2 (no associative arrays or GNU extensions).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT="${REPO_ROOT}/src/generated/database-schema.md"

CORE_DIR="${TASKER_CORE_DIR:-../tasker-core}"

# Resolve relative path from repo root
if [[ ! "${CORE_DIR}" = /* ]]; then
    CORE_DIR="${REPO_ROOT}/${CORE_DIR}"
fi

MIGRATIONS_DIR="${CORE_DIR}/migrations"
TABLES_SQL="${MIGRATIONS_DIR}/20260110000001_schema_and_tables.sql"
CONSTRAINTS_SQL="${MIGRATIONS_DIR}/20260110000002_constraints_and_indexes.sql"

# Validate source files exist
for f in "${TABLES_SQL}" "${CONSTRAINTS_SQL}"; do
    if [[ ! -f "${f}" ]]; then
        echo "ERROR: Migration file not found: ${f}"
        echo "Set TASKER_CORE_DIR to point to your tasker-core checkout."
        exit 1
    fi
done

echo "Generating database schema ER diagram..."
echo "  Source: ${MIGRATIONS_DIR}"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# ---------------------------------------------------------------------------
# Parse table definitions from migration 1
# Output: table_data file with TABLE|name and COL|table|col|type|pk lines
# ---------------------------------------------------------------------------
parse_tables() {
    local file="${TABLES_SQL}"
    local current_table=""
    local in_table=false
    local first_uuid_seen=false

    while IFS= read -r line; do
        local stripped
        stripped=$(echo "${line}" | sed 's/^[[:space:]]*//')

        # Detect CREATE TABLE
        if echo "${stripped}" | grep -q '^CREATE[[:space:]]*TABLE[[:space:]]'; then
            current_table=$(echo "${stripped}" | sed -E 's/CREATE TABLE (ONLY )?tasker\.([a-z_]+).*/\2/')
            in_table=true
            first_uuid_seen=false
            echo "TABLE|${current_table}"
            continue
        fi

        # Skip CREATE VIEW, CREATE TYPE, etc.
        if echo "${stripped}" | grep -q '^CREATE[[:space:]]*\(VIEW\|TYPE\|EXTENSION\|OR\)'; then
            in_table=false
            continue
        fi

        if [[ "${in_table}" != true ]]; then
            continue
        fi

        # End of CREATE TABLE
        case "${stripped}" in
            ")"*) in_table=false; continue ;;
        esac

        # Skip CONSTRAINT lines, empty lines
        if echo "${stripped}" | grep -q '^CONSTRAINT'; then
            continue
        fi
        if [[ -z "${stripped}" ]]; then
            continue
        fi

        # Parse column definition
        col_name=$(echo "${stripped}" | sed -E 's/^([a-z_]+)[[:space:]].*/\1/')
        # Validate it looks like a column name
        case "${col_name}" in
            [a-z]*)  ;; # valid
            *) continue ;;
        esac

        # Determine simplified type
        col_type="other"
        if echo "${stripped}" | grep -q 'uuid'; then
            col_type="uuid"
        elif echo "${stripped}" | grep -q 'character[[:space:]]*varying'; then
            col_type="varchar"
        elif echo "${stripped}" | grep -q 'integer'; then
            col_type="integer"
        elif echo "${stripped}" | grep -q 'boolean'; then
            col_type="boolean"
        elif echo "${stripped}" | grep -q 'timestamp'; then
            col_type="timestamp"
        elif echo "${stripped}" | grep -q 'jsonb'; then
            col_type="jsonb"
        elif echo "${stripped}" | grep -q 'text'; then
            col_type="text"
        elif echo "${stripped}" | grep -q 'bigint'; then
            col_type="bigint"
        elif echo "${stripped}" | grep -q 'tasker\.'; then
            col_type="enum"
        fi

        # Check if PK (first uuid column with DEFAULT uuid_generate_v7 and NOT NULL)
        is_pk="false"
        if [[ "${col_type}" == "uuid" ]] && [[ "${first_uuid_seen}" == false ]]; then
            if echo "${stripped}" | grep -q 'uuid_generate_v7'; then
                is_pk="true"
                first_uuid_seen=true
            fi
        fi

        echo "COL|${current_table}|${col_name}|${col_type}|${is_pk}"
    done < "${file}"
}

# ---------------------------------------------------------------------------
# Parse foreign key constraints from migration 2
# Output: FK lines with src_table|src_col|tgt_table|tgt_col
# ---------------------------------------------------------------------------
parse_foreign_keys() {
    local file="${CONSTRAINTS_SQL}"
    local current_src=""

    while IFS= read -r line; do
        # Track current table for FK context
        if echo "${line}" | grep -q 'ALTER[[:space:]]*TABLE'; then
            current_src=$(echo "${line}" | sed -E 's/.*tasker\.([a-z_]+).*/\1/')
        fi

        # Look for FOREIGN KEY lines (skip SQL comments)
        if echo "${line}" | grep -q '^[[:space:]]*--'; then
            continue
        fi
        if echo "${line}" | grep -q 'FOREIGN[[:space:]]*KEY'; then
            src_col=$(echo "${line}" | sed -E 's/.*FOREIGN KEY \(([^)]+)\).*/\1/')
            tgt_table=$(echo "${line}" | sed -E 's/.*REFERENCES tasker\.([a-z_]+)\(.*/\1/')
            tgt_col=$(echo "${line}" | sed -E 's/.*REFERENCES tasker\.[a-z_]+\(([^)]+)\).*/\1/')
            echo "${current_src}|${src_col}|${tgt_table}|${tgt_col}"
        fi
    done < "${file}"
}

# ---------------------------------------------------------------------------
# Collect parsed data into temp files
# ---------------------------------------------------------------------------
parse_tables > "${TMPDIR_WORK}/table_data.txt"
parse_foreign_keys > "${TMPDIR_WORK}/fk_data.txt"

# Extract table names
TABLES=()
while IFS='|' read -r type name rest; do
    if [[ "${type}" == "TABLE" ]]; then
        TABLES+=("${name}")
    fi
done < "${TMPDIR_WORK}/table_data.txt"

# ---------------------------------------------------------------------------
# Generate output
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "${OUTPUT}")"

{
    cat <<'HEADER'
# Database Schema

> Auto-generated from SQL migration analysis. Do not edit manually.
>
> Regenerate with: `cargo make generate-db-schema`

The Tasker database uses PostgreSQL with the `tasker` schema. All tables use UUID v7
primary keys for time-ordered identifiers. The schema supports PostgreSQL 17 (via
`pg_uuidv7` extension) and PostgreSQL 18+ (native `uuidv7()` function).

## Entity Relationship Diagram

```mermaid
erDiagram
HEADER

    # Emit table entities with columns
    for table in "${TABLES[@]}"; do
        echo "    ${table} {"
        while IFS='|' read -r type tbl col ctype is_pk; do
            if [[ "${type}" != "COL" ]] || [[ "${tbl}" != "${table}" ]]; then
                continue
            fi
            marker=""
            if [[ "${is_pk}" == "true" ]]; then
                marker=" PK"
            elif echo "${col}" | grep -q '_uuid$'; then
                if [[ "${is_pk}" != "true" ]]; then
                    marker=" FK"
                fi
            fi
            echo "        ${ctype} ${col}${marker}"
        done < "${TMPDIR_WORK}/table_data.txt"
        echo "    }"
    done

    echo ""

    # Emit relationships from foreign keys
    while IFS='|' read -r src_table src_col tgt_table tgt_col; do
        if [[ -n "${src_table}" ]] && [[ -n "${tgt_table}" ]]; then
            echo "    ${tgt_table} ||--o{ ${src_table} : \"${src_col}\""
        fi
    done < "${TMPDIR_WORK}/fk_data.txt"

    cat <<'FOOTER'
```

## Tables

FOOTER

    echo "| Table | Description |"
    echo "|-------|-------------|"
    echo "| \`task_namespaces\` | Multi-tenant namespace isolation for task definitions |"
    echo "| \`named_tasks\` | Reusable task templates with versioned configuration |"
    echo "| \`named_steps\` | Reusable step definitions referenced by task templates |"
    echo "| \`named_tasks_named_steps\` | Join table linking task templates to their step definitions |"
    echo "| \`tasks\` | Task instances created from templates with execution context |"
    echo "| \`workflow_steps\` | Individual step instances within a task execution |"
    echo "| \`workflow_step_edges\` | Directed graph of step dependencies (DAG edges) |"
    echo "| \`task_transitions\` | Event-sourced state change history for tasks (12-state machine) |"
    echo "| \`workflow_step_transitions\` | Event-sourced state change history for steps (10-state machine) |"
    echo "| \`workflow_step_result_audit\` | Lightweight audit trail for SOC2 compliance |"
    echo "| \`tasks_dlq\` | Dead Letter Queue for stuck task investigation and resolution |"

    echo ""
    echo "## Foreign Key Relationships"
    echo ""
    echo "| Source Table | Column | Target Table | Target Column |"
    echo "|-------------|--------|-------------|---------------|"

    while IFS='|' read -r src_table src_col tgt_table tgt_col; do
        if [[ -n "${src_table}" ]] && [[ -n "${tgt_table}" ]]; then
            echo "| \`${src_table}\` | \`${src_col}\` | \`${tgt_table}\` | \`${tgt_col}\` |"
        fi
    done < "${TMPDIR_WORK}/fk_data.txt"

    echo ""
    echo "---"
    echo ""
    echo "*Generated by \`generate-db-schema.sh\` from tasker-core SQL migration analysis*"

} > "${OUTPUT}"

echo "  Output: ${OUTPUT}"
echo "Database schema ER diagram generated (${#TABLES[@]} tables)."
