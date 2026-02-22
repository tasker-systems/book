# Microservices Coordination with Tasker

*How the diamond dependency pattern replaces custom circuit breakers and service coordination glue.*

> **Handler examples** use Ruby DSL syntax. See [Class-Based Handlers](../reference/class-based-handlers.md) for the class-based alternative. Full implementations in all four languages are linked at the bottom.

## The Problem

Your user registration flow touches four services: the user service (account creation), the billing service (payment profile), the preferences service (notification settings), and the notification service (welcome emails). Each service has its own API, its own failure modes, and its own retry characteristics.

You started with a sequential chain: create user, then billing, then preferences, then welcome email. It works, but it's slow — billing and preferences don't depend on each other, yet one waits for the other. When the billing service has a bad deploy and starts returning 500s, your entire registration pipeline backs up. You add a circuit breaker for billing, then another for preferences, then retry logic, then timeout handling. Now your "simple" registration flow is 400 lines of coordination code that's harder to reason about than the business logic it orchestrates.

The coordination logic isn't the value your team delivers. The value is in the business rules — how you create accounts, what billing tiers you support, which notification channels you enable. The wiring between services should be declarative.

## The Fragile Approach

A typical multi-service registration handler accumulates coordination concerns:

```python
def register_user(user_info):
    account = user_service.create(user_info)          # must complete first

    billing = retry(3, backoff=exp):                   # custom retry
        billing_service.setup(account.id, user_info.plan)
    preferences = retry(3, backoff=exp):               # custom retry
        preferences_service.init(account.id)

    wait_all(billing, preferences)                     # custom fan-out/fan-in

    notifications.send_welcome(account, billing, preferences)  # depends on both
    user_service.activate(account.id)                          # final step
```

Each `retry()` call is hand-rolled. The `wait_all()` is custom concurrency code. Error handling for partial failures (billing succeeded but preferences didn't) requires manual cleanup logic. And this pattern gets duplicated across every multi-service workflow in your codebase.

## The Tasker Approach

Tasker models this as a **diamond dependency pattern**: one step fans out to parallel branches that converge before the next step runs. The template declares the shape; the orchestrator handles concurrency, retries, and convergence.

### Task Template (YAML)

```yaml
name: user_registration
namespace_name: microservices
version: 1.0.0
description: "User registration workflow with microservices coordination"

steps:
  # Step 1: Create user account (must complete before anything else)
  - name: create_user_account
    description: "Create user account in user service with idempotency"
    handler:
      callable: Microservices::StepHandlers::CreateUserAccountHandler
    dependencies: []
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      initial_delay: 2
      max_delay: 30

  # Steps 2-3: Run in PARALLEL (both depend only on create_user_account)
  - name: setup_billing_profile
    description: "Setup billing profile in billing service"
    handler:
      callable: Microservices::StepHandlers::SetupBillingProfileHandler
    dependencies:
      - create_user_account
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      initial_delay: 2
      max_delay: 30

  - name: initialize_preferences
    description: "Initialize user preferences in preferences service"
    handler:
      callable: Microservices::StepHandlers::InitializePreferencesHandler
    dependencies:
      - create_user_account
    retry:
      retryable: true
      max_attempts: 3
      backoff: exponential
      initial_delay: 2
      max_delay: 30

  # Step 4: CONVERGENCE — waits for both billing AND preferences
  - name: send_welcome_sequence
    description: "Send welcome emails via notification service"
    handler:
      callable: Microservices::StepHandlers::SendWelcomeSequenceHandler
    dependencies:
      - setup_billing_profile
      - initialize_preferences
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      initial_delay: 2
      max_delay: 20

  # Step 5: Final status update
  - name: update_user_status
    description: "Update user status to active in user service"
    handler:
      callable: Microservices::StepHandlers::UpdateUserStatusHandler
    dependencies:
      - send_welcome_sequence
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
```

The diamond pattern emerges from the dependency declarations:

```
create_user_account
    ├──→ setup_billing_profile ──────┐
    └──→ initialize_preferences ─────┼──→ send_welcome_sequence → update_user_status
                                     ┘
```

Steps 2 and 3 both depend on step 1, so they run **in parallel** once account creation completes. Step 4 depends on **both** steps 2 and 3, so it waits for the slower of the two — this is the convergence point. No custom concurrency code needed.

> **Full template**: [microservices\_user\_registration.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/microservices_user_registration.yaml)

### Step Handlers

#### CreateUserAccountHandler — Idempotent Account Creation

The first step creates the user account. Since it's the entry point, the DSL declares a typed input model that handles validation.

**Type definition** (the contract):

```ruby
# app/services/types.rb
module Types
  module Microservices
    class CreateUserAccountInput < Types::InputStruct
      attribute :email, Types::String
      attribute :name, Types::String.optional
      attribute :plan, Types::String.optional
      attribute :marketing_consent, Types::Bool.optional
    end
  end
end
```

**Handler** (DSL declaration + service delegation):

```ruby
# app/handlers/microservices/step_handlers/create_user_account_handler.rb
module Microservices
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    CreateUserAccountHandler = step_handler(
      'Microservices::StepHandlers::CreateUserAccountHandler',
      inputs: Types::Microservices::CreateUserAccountInput
    ) do |inputs:, context:|
      Microservices::Service.create_user_account(input: inputs)
    end
  end
end
```

The `inputs:` config extracts fields from the task context and validates them against the `Dry::Struct` type. Input validation (required email, format checks, blocked domains) lives in the service function — the handler stays thin. Validation failures raise `PermanentError` since bad input can't be fixed by retrying.

> **Full implementations**: [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/microservices/) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/microservices.ts)

#### SendWelcomeSequenceHandler — Multi-Dependency Convergence

The welcome sequence handler demonstrates the convergence pattern — the diamond's bottom vertex. Three `depends_on` entries compose the function signature with typed results from all upstream branches.

```ruby
module Microservices
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    SendWelcomeSequenceHandler = step_handler(
      'Microservices::StepHandlers::SendWelcomeSequenceHandler',
      depends_on: {
        account_data: ['create_user_account', Types::Microservices::CreateUserResult],
        billing_data: ['setup_billing_profile', Types::Microservices::SetupBillingResult],
        preferences_data: ['initialize_preferences', Types::Microservices::InitPreferencesResult]
      }
    ) do |account_data:, billing_data:, preferences_data:, context:|
      Microservices::Service.send_welcome_sequence(
        account_data: account_data,
        billing_data: billing_data,
        preferences_data: preferences_data,
      )
    end
  end
end
```

The `depends_on:` hash declares three upstream step results, each typed with a `Dry::Struct` result model. The orchestrator guarantees that all three have completed successfully before this handler runs. The service function composes the welcome content — adapting based on the billing profile (trial status) and preferences (notification channels), data that was gathered in parallel.

The parallel steps that feed into this convergence point use the same pattern:

```ruby
# Runs in parallel with InitializePreferencesHandler (both depend on create_user_account)
SetupBillingProfileHandler = step_handler(
  'Microservices::StepHandlers::SetupBillingProfileHandler',
  depends_on: { account_data: ['create_user_account', Types::Microservices::CreateUserResult] }
) do |account_data:, context:|
  Microservices::Service.setup_billing_profile(account_data: account_data)
end
```

> **Full implementations**: [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/microservices/) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/microservices.ts)

### Creating a Task

```ruby
task = TaskerCore::Client.create_task(
  name:      'user_registration',
  namespace: 'microservices',
  context:   {
    user_info: {
      email: 'new.user@example.com',
      name:  'Jane Developer',
      plan:  'pro',
      source: 'signup_form'
    }
  }
)
```

## Key Concepts

- **Diamond dependency pattern**: One step fans out to parallel branches that converge before the workflow continues. Declare it with `dependencies` — no concurrency primitives needed.
- **Typed convergence**: The `depends_on:` hash in the DSL composes the convergence handler's signature from three typed upstream results. No manual `get_dependency_result()` calls or nil checks.
- **Service coordination without custom circuit breakers**: Each step's retry policy acts as a per-service circuit breaker. If billing fails 3 times, that step fails permanently — but preferences continues independently. No shared circuit breaker state to manage.
- **Dependency-driven personalization**: The convergence handler's service function composes data from all upstream branches to create personalized outputs (welcome messages tailored to plan, trial status, and notification preferences).

## Full Implementations

The complete user registration workflow is implemented in all four supported languages:

| Language | Handlers | Template |
|----------|----------|----------|
| Ruby (Rails) | [handlers/microservices/](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/microservices/) | [microservices\_user\_registration.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/config/tasker/templates/microservices_user_registration.yaml) |
| TypeScript (Bun/Hono) | [handlers/microservices.ts](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/microservices.ts) | [microservices\_user\_registration.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/config/tasker/templates/microservices_user_registration.yaml) |
| Python (FastAPI) | [handlers/microservices.py](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/app/handlers/microservices.py) | [microservices\_user\_registration.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app/config/tasker/templates/microservices_user_registration.yaml) |
| Rust (Axum) | [handlers/microservices.rs](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/src/handlers/microservices.rs) | [microservices\_user\_registration.yaml](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/axum-app/config/tasker/templates/microservices_user_registration.yaml) |

## What's Next

Workflows within a single team are manageable, but what happens when multiple teams define workflows with overlapping names? In [Post 04: Team Scaling with Namespaces](post-04-team-scaling.md), we'll see how Tasker's namespace system lets teams like Customer Success and Payments each own a `process_refund` workflow without naming conflicts — and how cross-namespace coordination enables clean team boundaries.

---

*See this pattern implemented in all four frameworks on the [Example Apps](../getting-started/example-apps.md) page.*
