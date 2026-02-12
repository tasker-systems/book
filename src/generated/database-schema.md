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
    named_steps {
        uuid named_step_uuid PK
        varchar name
        varchar description
        timestamp created_at
        timestamp updated_at
    }
    named_tasks {
        uuid named_task_uuid PK
        uuid task_namespace_uuid FK
        varchar name
        varchar description
        varchar version
        jsonb configuration
        timestamp created_at
        timestamp updated_at
    }
    named_tasks_named_steps {
        uuid ntns_uuid PK
        uuid named_task_uuid FK
        uuid named_step_uuid FK
        boolean default_retryable
        integer default_max_attempts
        timestamp created_at
        timestamp updated_at
    }
    workflow_step_edges {
        uuid workflow_step_edge_uuid PK
        uuid from_step_uuid FK
        uuid to_step_uuid FK
        varchar name
        timestamp created_at
        timestamp updated_at
    }
    workflow_steps {
        uuid workflow_step_uuid PK
        uuid task_uuid FK
        uuid named_step_uuid FK
        boolean retryable
        integer max_attempts
        boolean in_process
        boolean processed
        timestamp processed_at
        integer attempts
        timestamp last_attempted_at
        integer backoff_request_seconds
        jsonb inputs
        jsonb results
        timestamp created_at
        timestamp updated_at
        integer priority
        jsonb checkpoint
    }
    task_namespaces {
        uuid task_namespace_uuid PK
        varchar name
        varchar description
        timestamp created_at
        timestamp updated_at
    }
    task_transitions {
        uuid task_transition_uuid PK
        uuid task_uuid FK
        varchar to_state
        varchar from_state
        jsonb metadata
        integer sort_key
        boolean most_recent
        timestamp created_at
        timestamp updated_at
        uuid processor_uuid FK
        jsonb transition_metadata
    }
    tasks {
        uuid task_uuid PK
        uuid named_task_uuid FK
        boolean complete
        timestamp requested_at
        timestamp completed_at
        varchar initiator
        varchar source_system
        varchar reason
        jsonb tags
        jsonb context
        varchar identity_hash
        timestamp created_at
        timestamp updated_at
        integer priority
        uuid correlation_id
        uuid parent_correlation_id
    }
    tasks_dlq {
        uuid dlq_entry_uuid PK
        uuid task_uuid FK
        varchar original_state
        enum dlq_reason
        timestamp dlq_timestamp
        enum resolution_status
        timestamp resolution_timestamp
        text resolution_notes
        varchar resolved_by
        jsonb task_snapshot
        jsonb metadata
        timestamp created_at
        timestamp updated_at
    }
    workflow_step_result_audit {
        uuid workflow_step_result_audit_uuid PK
        uuid workflow_step_uuid FK
        uuid workflow_step_transition_uuid FK
        uuid task_uuid FK
        timestamp recorded_at
        uuid worker_uuid FK
        uuid correlation_id
        boolean success
        bigint execution_time_ms
        timestamp created_at
        timestamp updated_at
    }
    workflow_step_transitions {
        uuid workflow_step_transition_uuid PK
        uuid workflow_step_uuid FK
        varchar to_state
        varchar from_state
        jsonb metadata
        integer sort_key
        boolean most_recent
        timestamp created_at
        timestamp updated_at
    }

    -- FOREIGN KEY CONSTRAINTS ||--o{ workflow_steps : "-- FOREIGN KEY CONSTRAINTS"
    named_steps ||--o{ named_tasks_named_steps : "named_step_uuid"
    named_tasks ||--o{ named_tasks_named_steps : "named_task_uuid"
    task_namespaces ||--o{ named_tasks : "task_namespace_uuid"
    tasks ||--o{ task_transitions : "task_uuid"
    tasks ||--o{ tasks_dlq : "task_uuid"
    named_tasks ||--o{ tasks : "named_task_uuid"
    workflow_steps ||--o{ workflow_step_edges : "from_step_uuid"
    workflow_steps ||--o{ workflow_step_edges : "to_step_uuid"
    workflow_step_transitions ||--o{ workflow_step_result_audit : "workflow_step_transition_uuid"
    tasks ||--o{ workflow_step_result_audit : "task_uuid"
    workflow_steps ||--o{ workflow_step_result_audit : "workflow_step_uuid"
    workflow_steps ||--o{ workflow_step_transitions : "workflow_step_uuid"
    named_steps ||--o{ workflow_steps : "named_step_uuid"
    tasks ||--o{ workflow_steps : "task_uuid"
```

## Tables

| Table | Description |
|-------|-------------|
| `task_namespaces` | Multi-tenant namespace isolation for task definitions |
| `named_tasks` | Reusable task templates with versioned configuration |
| `named_steps` | Reusable step definitions referenced by task templates |
| `named_tasks_named_steps` | Join table linking task templates to their step definitions |
| `tasks` | Task instances created from templates with execution context |
| `workflow_steps` | Individual step instances within a task execution |
| `workflow_step_edges` | Directed graph of step dependencies (DAG edges) |
| `task_transitions` | Event-sourced state change history for tasks (12-state machine) |
| `workflow_step_transitions` | Event-sourced state change history for steps (10-state machine) |
| `workflow_step_result_audit` | Lightweight audit trail for SOC2 compliance |
| `tasks_dlq` | Dead Letter Queue for stuck task investigation and resolution |

## Foreign Key Relationships

| Source Table | Column | Target Table | Target Column |
|-------------|--------|-------------|---------------|
| `workflow_steps` | `-- FOREIGN KEY CONSTRAINTS` | `-- FOREIGN KEY CONSTRAINTS` | `-- FOREIGN KEY CONSTRAINTS` |
| `named_tasks_named_steps` | `named_step_uuid` | `named_steps` | `named_step_uuid` |
| `named_tasks_named_steps` | `named_task_uuid` | `named_tasks` | `named_task_uuid` |
| `named_tasks` | `task_namespace_uuid` | `task_namespaces` | `task_namespace_uuid` |
| `task_transitions` | `task_uuid` | `tasks` | `task_uuid` |
| `tasks_dlq` | `task_uuid` | `tasks` | `task_uuid` |
| `tasks` | `named_task_uuid` | `named_tasks` | `named_task_uuid` |
| `workflow_step_edges` | `from_step_uuid` | `workflow_steps` | `workflow_step_uuid` |
| `workflow_step_edges` | `to_step_uuid` | `workflow_steps` | `workflow_step_uuid` |
| `workflow_step_result_audit` | `workflow_step_transition_uuid` | `workflow_step_transitions` | `workflow_step_transition_uuid` |
| `workflow_step_result_audit` | `task_uuid` | `tasks` | `task_uuid` |
| `workflow_step_result_audit` | `workflow_step_uuid` | `workflow_steps` | `workflow_step_uuid` |
| `workflow_step_transitions` | `workflow_step_uuid` | `workflow_steps` | `workflow_step_uuid` |
| `workflow_steps` | `named_step_uuid` | `named_steps` | `named_step_uuid` |
| `workflow_steps` | `task_uuid` | `tasks` | `task_uuid` |

---

*Generated by `generate-db-schema.sh` from tasker-core SQL migration analysis*
