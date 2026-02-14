# Microservices Coordination with Tasker

*How the diamond dependency pattern replaces custom circuit breakers and service coordination glue.*

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

The first step creates the user account. Since it's the entry point for the entire workflow, it validates inputs thoroughly.

**Ruby (Rails)**

```ruby
class CreateUserAccountHandler < TaskerCore::StepHandler::Base
  EMAIL_REGEX = /\A[^@\s]+@[^@\s]+\.[^@\s]+\z/
  BLOCKED_DOMAINS = %w[tempmail.com throwaway.email mailinator.com].freeze

  def call(context)
    user_info = context.get_input_or('user_info', {})
    user_info = user_info.deep_symbolize_keys

    email = user_info[:email]
    name  = user_info[:name]
    plan  = user_info[:plan] || 'free'

    raise TaskerCore::Errors::PermanentError.new(
      'Email address is required', error_code: 'MISSING_EMAIL'
    ) if email.blank?

    raise TaskerCore::Errors::PermanentError.new(
      "Invalid email format: #{email}", error_code: 'INVALID_EMAIL'
    ) unless email.match?(EMAIL_REGEX)

    email_domain = email.split('@').last&.downcase
    if BLOCKED_DOMAINS.include?(email_domain)
      raise TaskerCore::Errors::PermanentError.new(
        "Disposable email addresses are not allowed: #{email_domain}",
        error_code: 'BLOCKED_EMAIL_DOMAIN'
      )
    end

    user_id = "usr_#{SecureRandom.hex(12)}"

    TaskerCore::Types::StepHandlerCallResult.success(
      result: {
        user_id: user_id,
        email: email.downcase,
        name: name,
        plan: plan,
        status: 'created',
        email_verified: false,
        verification_token: SecureRandom.urlsafe_base64(32),
        created_at: Time.current.iso8601
      }
    )
  end
end
```

**TypeScript (Bun/Hono)**

```typescript
export class CreateUserHandler extends StepHandler {
  static handlerName = 'Microservices.StepHandlers.CreateUserAccountHandler';

  async call(context: StepContext): Promise<StepHandlerResult> {
    const userInfo = (context.getInput('user_info') || {}) as {
      email?: string; name?: string; plan?: string;
    };

    if (!userInfo.email) {
      return this.failure('Email is required', ErrorType.PERMANENT_ERROR, false);
    }

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!emailRegex.test(userInfo.email)) {
      return this.failure(
        `Invalid email format: ${userInfo.email}`, ErrorType.PERMANENT_ERROR, false
      );
    }

    const userId = crypto.randomUUID();
    return this.success({
      user_id: userId,
      email: userInfo.email,
      name: userInfo.name,
      plan: userInfo.plan || 'free',
      status: 'created',
      created_at: new Date().toISOString(),
    });
  }
}
```

Note the use of `get_input_or('user_info', {})` in Ruby — this provides a default value if the input key is missing, preventing nil errors. Both implementations use permanent errors for validation failures (bad email, blocked domain) since these can't be fixed by retrying.

> **Full implementations**: [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/microservices/create_user_account_handler.rb) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/microservices.ts)

#### SendWelcomeSequenceHandler — Multi-Dependency Convergence

The welcome sequence handler demonstrates the convergence pattern. It pulls results from **three** upstream steps — the account, billing profile, and preferences — and composes them into a personalized notification sequence.

**Ruby (Rails)**

```ruby
class SendWelcomeSequenceHandler < TaskerCore::StepHandler::Base
  def call(context)
    account_data     = context.get_dependency_result('create_user_account')
    billing_data     = context.get_dependency_result('setup_billing_profile')
    preferences_data = context.get_dependency_result('initialize_preferences')

    raise TaskerCore::Errors::PermanentError.new(
      'Upstream data not available for welcome sequence',
      error_code: 'MISSING_DEPENDENCIES'
    ) if account_data.nil? || billing_data.nil? || preferences_data.nil?

    email    = account_data['email']
    name     = account_data['name']
    plan     = account_data['plan']
    has_trial = billing_data['trial_days'].to_i > 0
    notifications = preferences_data.dig('preferences', 'notifications') || {}

    messages_sent = []

    # Welcome email (always)
    messages_sent << { channel: 'email', type: 'welcome', recipient: email,
                       subject: "Welcome to Tasker, #{name}!" }

    # Trial notification (if applicable)
    if has_trial
      messages_sent << { channel: 'email', type: 'trial_started', recipient: email,
                         subject: "Your #{plan.capitalize} trial has started" }
    end

    # Push notification (if user opted in)
    if notifications['push'] == true
      messages_sent << { channel: 'push', type: 'welcome',
                         body: "Your #{plan} account is ready. Let's get started!" }
    end

    TaskerCore::Types::StepHandlerCallResult.success(
      result: {
        user_id: account_data['user_id'],
        channels_used: messages_sent.map { |m| m[:channel] }.uniq,
        messages_sent: messages_sent.size,
        status: 'sent',
        sent_at: Time.current.iso8601
      }
    )
  end
end
```

The handler calls `get_dependency_result()` for each of the three upstream steps. The orchestrator guarantees that all three have completed successfully before this handler runs. The welcome content adapts based on the billing profile (trial status) and preferences (notification channels) — data that was gathered in parallel.

> **Full implementation**: [Rails](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app/app/handlers/microservices/send_welcome_sequence_handler.rb) | [Bun/Hono](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/bun-app/src/handlers/microservices.ts)

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
- **Parallel branches that converge**: `setup_billing_profile` and `initialize_preferences` run concurrently because they share the same single dependency. `send_welcome_sequence` waits for both because it lists both as dependencies.
- **Service coordination without custom circuit breakers**: Each step's retry policy acts as a per-service circuit breaker. If billing fails 3 times, that step fails permanently — but preferences continues independently. No shared circuit breaker state to manage.
- **Dependency-driven personalization**: The convergence handler composes data from all upstream branches to create personalized outputs (welcome messages tailored to plan, trial status, and notification preferences).

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
