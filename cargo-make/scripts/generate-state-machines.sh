#!/usr/bin/env bash
# =============================================================================
# Generate State Machine Diagrams (Mermaid)
# =============================================================================
#
# Parses the task and step state machine Rust source files to extract state
# transitions, then generates Mermaid stateDiagram-v2 charts.
#
# Source files:
#   tasker-shared/src/state_machine/task_state_machine.rs
#   tasker-shared/src/state_machine/step_state_machine.rs
#
# Environment:
#   TASKER_CORE_DIR - Path to tasker-core repo (default: ../tasker-core)
#
# Compatible with macOS bash 3.2 (no associative arrays or GNU extensions).
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
OUTPUT="${REPO_ROOT}/src/generated/state-machine-diagrams.md"

CORE_DIR="${TASKER_CORE_DIR:-../tasker-core}"

# Resolve relative path from repo root
if [[ ! "${CORE_DIR}" = /* ]]; then
    CORE_DIR="${REPO_ROOT}/${CORE_DIR}"
fi

SM_DIR="${CORE_DIR}/tasker-shared/src/state_machine"
TASK_SM="${SM_DIR}/task_state_machine.rs"
STEP_SM="${SM_DIR}/step_state_machine.rs"

# Validate source files exist
for f in "${TASK_SM}" "${STEP_SM}"; do
    if [[ ! -f "${f}" ]]; then
        echo "ERROR: State machine source not found: ${f}"
        echo "Set TASKER_CORE_DIR to point to your tasker-core checkout."
        exit 1
    fi
done

echo "Generating state machine diagrams..."
echo "  Source: ${SM_DIR}"

TMPDIR_WORK=$(mktemp -d)
trap 'rm -rf "${TMPDIR_WORK}"' EXIT

# ---------------------------------------------------------------------------
# Extract transitions using sed
# Processes the match block and outputs: from|event|to|guard
# ---------------------------------------------------------------------------
extract_transitions() {
    local file="$1"

    # Extract lines between "let target = match" and "Ok(target)"
    # Join multi-line match arms (where => { State } spans multiple lines)
    # Then process each match arm
    sed -n '/let target = match/,/Ok(target)/p' "${file}" \
        | sed '/let target = match/d; /Ok(target)/d' \
        | sed '/^[[:space:]]*$/d' \
        | sed '/^[[:space:]]*\/\//d' \
        | sed '/from_state.*=>/d' \
        | sed '/return Err/d' \
        | sed 's/[[:space:]]*$//' \
        | sed -E 's/(TaskState|TaskEvent|WorkflowStepState|StepEvent):://g' \
        > "${TMPDIR_WORK}/raw_match.txt"

    # Join multi-line arms: if a line ends with "=> {", join with next non-empty line
    # This handles patterns like:
    #   (InProgress, EnqueueForOrchestration(_)) => {
    #       EnqueuedForOrchestration
    #   }
    awk '
    /=> \{[[:space:]]*$/ {
        # Line ends with => {, start accumulating
        acc = $0
        getline
        # Skip blank lines
        while ($0 ~ /^[[:space:]]*$/) getline
        # Append the state name
        acc = acc " " $0
        # Read closing brace
        getline
        print acc
        next
    }
    { print }
    ' "${TMPDIR_WORK}/raw_match.txt" \
        | while IFS= read -r line; do
            # Skip lines that don't start with ( after stripping
            stripped=$(echo "${line}" | sed 's/^[[:space:]]*//')
            case "${stripped}" in
                "("*) ;;
                *) continue ;;
            esac

            # Check for guard condition
            guard=""
            if echo "${stripped}" | grep -q ' if '; then
                guard=$(echo "${stripped}" | sed -E 's/.*if ([^=]+)=>.*/\1/' | sed 's/[[:space:]]*$//')
            fi

            # Extract from_state: text between first ( and first ,
            from=$(echo "${stripped}" | sed -E 's/^\(([^,]+),.*/\1/' | tr -d ' ')

            # Extract event: text between , and ) before =>
            event=$(echo "${stripped}" | sed -E 's/^\([^,]+,[[:space:]]*([^)]+)\).*/\1/')
            # Remove payload from event (e.g., ReadyStepsFound(_) -> ReadyStepsFound)
            event=$(echo "${event}" | sed -E 's/\(.*$//' | tr -d ' ')

            # Extract to_state: text after =>
            to=$(echo "${stripped}" | sed -E 's/.*=>[[:space:]]*//')
            # Remove trailing comma, braces, etc
            to=$(echo "${to}" | sed -E 's/[{},]//g; s/[[:space:]]*$//' | tr -d ' ')

            # Skip empty values
            if [[ -z "${from}" ]] || [[ -z "${to}" ]] || [[ -z "${event}" ]]; then
                continue
            fi

            echo "${from}|${event}|${to}|${guard}"
        done
}

# ---------------------------------------------------------------------------
# Generate task state machine transitions
# ---------------------------------------------------------------------------
extract_transitions "${TASK_SM}" > "${TMPDIR_WORK}/task_transitions.txt"
extract_transitions "${STEP_SM}" > "${TMPDIR_WORK}/step_transitions.txt"

task_count=$(wc -l < "${TMPDIR_WORK}/task_transitions.txt" | tr -d ' ')
step_count=$(wc -l < "${TMPDIR_WORK}/step_transitions.txt" | tr -d ' ')

# ---------------------------------------------------------------------------
# Generate output
# ---------------------------------------------------------------------------
mkdir -p "$(dirname "${OUTPUT}")"

{
    cat <<'HEADER'
# State Machine Diagrams

> Auto-generated from Rust source analysis. Do not edit manually.
>
> Regenerate with: `cargo make generate-state-machines`

Tasker uses two state machines to manage the lifecycle of tasks and workflow steps.
Both are implemented in `tasker-shared/src/state_machine/`.

## Task State Machine

The task state machine manages the overall lifecycle of a task through 12 states.
Tasks progress from `Pending` through initialization, step enqueuing, processing,
and evaluation phases, with support for dependency waiting, retry, and manual resolution.

```mermaid
stateDiagram-v2
HEADER

    # Initial and terminal states
    echo "    [*] --> Pending"
    echo "    Complete --> [*]"
    echo "    Error --> [*]"
    echo "    Cancelled --> [*]"
    echo "    ResolvedManually --> [*]"
    echo ""

    # Emit task transitions
    while IFS='|' read -r from event to guard; do
        if [[ -z "${from}" ]] || [[ -z "${to}" ]]; then
            continue
        fi
        label="${event}"
        if [[ -n "${guard}" ]]; then
            label="${event} [guard]"
        fi
        if [[ "${from}" == "state" ]]; then
            # Wildcard match for non-terminal states - expand to key states
            for s in Pending Initializing EnqueuingSteps StepsInProcess EvaluatingResults WaitingForDependencies WaitingForRetry BlockedByFailures; do
                echo "    ${s} --> ${to} : ${label}"
            done
        elif [[ "${from}" == "_" ]]; then
            echo "    note right of ${to} : From any state via ${event}"
        else
            echo "    ${from} --> ${to} : ${label}"
        fi
    done < "${TMPDIR_WORK}/task_transitions.txt"

    cat <<'MID1'
```

### Task State Transitions

| From State | Event | To State | Notes |
|-----------|-------|----------|-------|
MID1

    while IFS='|' read -r from event to guard; do
        if [[ -z "${from}" ]] || [[ -z "${to}" ]]; then
            continue
        fi
        notes=""
        if [[ -n "${guard}" ]]; then
            notes="Guard: \`${guard}\`"
        fi
        display_from="${from}"
        if [[ "${from}" == "state" ]] || [[ "${from}" == "_" ]]; then
            display_from="*(any non-terminal)*"
        fi
        echo "| ${display_from} | ${event} | ${to} | ${notes} |"
    done < "${TMPDIR_WORK}/task_transitions.txt"

    cat <<'MID2'

## Workflow Step State Machine

The workflow step state machine manages individual step execution through 10 states.
Steps follow a worker-to-orchestration handoff pattern: workers execute steps and
enqueue results for orchestration processing.

```mermaid
stateDiagram-v2
MID2

    # Initial and terminal states
    echo "    [*] --> Pending"
    echo "    Complete --> [*]"
    echo "    Error --> [*]"
    echo "    Cancelled --> [*]"
    echo "    ResolvedManually --> [*]"
    echo ""

    # Emit step transitions
    while IFS='|' read -r from event to guard; do
        if [[ -z "${from}" ]] || [[ -z "${to}" ]]; then
            continue
        fi
        if [[ "${from}" == "_" ]]; then
            echo "    note right of ${to} : From any state via ${event}"
        else
            echo "    ${from} --> ${to} : ${event}"
        fi
    done < "${TMPDIR_WORK}/step_transitions.txt"

    cat <<'MID3'
```

### Workflow Step State Transitions

| From State | Event | To State |
|-----------|-------|----------|
MID3

    while IFS='|' read -r from event to guard; do
        if [[ -z "${from}" ]] || [[ -z "${to}" ]]; then
            continue
        fi
        display_from="${from}"
        if [[ "${from}" == "_" ]]; then
            display_from="*(any state)*"
        fi
        echo "| ${display_from} | ${event} | ${to} |"
    done < "${TMPDIR_WORK}/step_transitions.txt"

    echo ""
    echo "---"
    echo ""
    echo "*Generated by \`generate-state-machines.sh\` from tasker-core Rust source analysis*"

} > "${OUTPUT}"

echo "  Output: ${OUTPUT}"
echo "State machine diagrams generated (${task_count} task transitions, ${step_count} step transitions)."
