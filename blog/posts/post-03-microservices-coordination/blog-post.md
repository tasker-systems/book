# Microservices Orchestration Without the Chaos

*How one team tamed their distributed system nightmare into a coordinated symphony*

---

## The Distributed System Reality Check

Eight months after conquering their data pipeline demons, Sarah's team at GrowthCorp was riding high. Their customer analytics ran like clockwork, delivering fresh insights every morning without a single 3 AM alert.

Then the architecture team made an announcement that filled Sarah with dread:

"We're breaking up the monolith! Each domain team will own their services. User management, inventory, payments, notifications - all separate services with their own databases and APIs."

"It'll be great!" proclaimed Marcus, the newly hired DevOps engineer. "Microservices give us independence, scalability, and faster deployments!"

Sarah had seen this movie before. She knew what was coming.

Three weeks after the "great decomposition," her phone started buzzing again. But this time it wasn't data pipelines - it was something far worse.

> **Alert**: User registration completion rate down 40%
> **Symptoms**: Registration starts but never completes
> **Services involved**: Users, Billing, Notifications, Preferences
> **Debug path**: Good luck.

What used to be a simple user registration flow had become a distributed nightmare spanning 4 services with no coordination, no failure handling, and no visibility when things went wrong.

## The Microservices Horror Show

Here's what their "improved" user registration looked like:

```ruby
class UserRegistrationService
  def register_user(user_params)
    # Step 1: Create user in UserService
    user_response = HTTParty.post("#{USER_SERVICE_URL}/users", {
      body: user_params.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 30
    })

    raise "User creation failed" unless user_response.success?
    user_id = user_response.parsed_response['id']

    # Step 2: Create billing profile
    billing_response = HTTParty.post("#{BILLING_SERVICE_URL}/profiles", {
      body: { user_id: user_id, plan: 'free' }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 30
    })

    raise "Billing creation failed" unless billing_response.success?

    # Step 3: Set up preferences
    prefs_response = HTTParty.post("#{PREFERENCES_SERVICE_URL}/preferences", {
      body: { user_id: user_id, defaults: true }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 30
    })

    raise "Preferences creation failed" unless prefs_response.success?

    # Step 4: Send welcome email
    email_response = HTTParty.post("#{NOTIFICATION_SERVICE_URL}/welcome", {
      body: { user_id: user_id, email: user_params[:email] }.to_json,
      headers: { 'Content-Type' => 'application/json' },
      timeout: 30
    })

    raise "Email sending failed" unless email_response.success?

    { user_id: user_id, status: 'completed' }
  rescue => e
    # What do we do here? User might be created but billing failed...
    logger.error "Registration failed: #{e.message}"
    raise
  end
end
```

**What went wrong constantly:**
- **BillingService timeout**: User created, no billing profile, registration "failed"
- **PreferencesService 500 error**: User and billing exist, but preferences missing
- **NotificationService rate limiting**: Everything created, no welcome email
- **Network hiccups**: Random timeouts causing partial registrations
- **Service deployments**: Any service restart broke in-flight registrations

The worst part? When something failed, they had **no idea what state the user was in**. Marcus spent his first month writing "cleanup scripts" to reconcile partially created users across services.

## The Orchestrated Solution

After their third weekend debugging partial registrations, Sarah's team applied the same Tasker patterns that had saved their checkout and data pipeline. But this time, they used Tasker's YAML configuration to clearly separate the workflow structure from the business logic:

```yaml
# config/tasker/tasks/user_management/user_registration_handler.yaml
task_name: user_registration
namespace: user_management
version: "2.6.0"
description: "Orchestrated user registration across microservices"

# Input validation schema
schema:
  type: object
  required: ['email', 'name']
  properties:
    email:
      type: string
      format: email
    name:
      type: string
      minLength: 1
    phone:
      type: string
    plan:
      type: string
      enum: ['free', 'pro', 'enterprise']
      default: 'free'
    marketing_consent:
      type: boolean
      default: false
    correlation_id:
      type: string
      description: "For distributed tracing"

step_templates:
  - name: create_user_account
    description: "Create user account in UserService"
    handler_class: "UserManagement::StepHandlers::CreateUserAccountHandler"
    default_retryable: true
    default_retry_limit: 3
    handler_config:
      timeout_seconds: 30
      service: "user_service"

  - name: setup_billing_profile
    description: "Create billing profile in BillingService"
    depends_on_steps: ["create_user_account"]
    handler_class: "UserManagement::StepHandlers::SetupBillingProfileHandler"
    default_retryable: true
    default_retry_limit: 3
    handler_config:
      timeout_seconds: 30
      service: "billing_service"

  - name: initialize_preferences
    description: "Set up user preferences in PreferencesService"
    depends_on_steps: ["create_user_account"]  # Runs parallel to billing
    handler_class: "UserManagement::StepHandlers::InitializePreferencesHandler"
    default_retryable: true
    default_retry_limit: 3
    handler_config:
      timeout_seconds: 20
      service: "preferences_service"

  - name: send_welcome_sequence
    description: "Send welcome email via NotificationService"
    depends_on_steps: ["setup_billing_profile", "initialize_preferences"]
    handler_class: "UserManagement::StepHandlers::SendWelcomeSequenceHandler"
    default_retryable: true
    default_retry_limit: 5  # Email services are often flaky
    handler_config:
      timeout_seconds: 15
      service: "notification_service"

  - name: update_user_status
    description: "Mark user registration as complete"
    depends_on_steps: ["send_welcome_sequence"]
    handler_class: "UserManagement::StepHandlers::UpdateUserStatusHandler"
    default_retryable: true
    default_retry_limit: 2
    handler_config:
      timeout_seconds: 10
      service: "user_service"
```

And a focused task handler with just the business logic:

```ruby
# app/tasks/user_management/user_registration_handler.rb
module UserManagement
  class UserRegistrationHandler < Tasker::ConfiguredTask

    # Runtime step dependency and configuration customization
    def establish_step_dependencies_and_defaults(task, steps)
      # Generate correlation ID for distributed tracing
      correlation_id = task.context['correlation_id'] || generate_correlation_id
      task.annotations['correlation_id'] = correlation_id
      
      # Adjust timeouts for enterprise customers
      if task.context['plan'] == 'enterprise'
        billing_step = steps.find { |s| s.name == 'setup_billing_profile' }
        if billing_step
          billing_step.retry_limit = 5
          billing_step.handler_config = billing_step.handler_config.merge(
            timeout_seconds: 45
          )
        end
      end
      
      # Add monitoring annotations for all steps
      steps.each do |step|
        step.annotations['correlation_id'] = correlation_id
        step.annotations['plan_type'] = task.context['plan'] || 'free'
      end
    end

    private

    def generate_correlation_id
      "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
    end
  end
end
```

## Circuit Breaker Pattern for Service Resilience

The real innovation was adding circuit breaker patterns to prevent cascade failures:

```ruby
# app/tasks/user_management/step_handlers/create_user_account_handler.rb
module UserManagement
  module StepHandlers
    class CreateUserAccountHandler < ApiBaseHandler

      def process(task, sequence, step)
        user_data = extract_user_data(task.context)
        
        log_structured_info("Creating user account", {
          email: user_data[:email],
          plan: task.context['plan']
        })
        
        response = with_circuit_breaker('user_service') do
          with_timeout(30) do
            http_client.post("#{user_service_url}/users", {
              body: user_data.to_json,
              headers: default_headers,
              timeout: 30
            })
          end
        end

        case response.code
        when 201
          # User created successfully
          user_response = response.parsed_response
          log_structured_info("User account created", { user_id: user_response['id'] })
          
          {
            user_id: user_response['id'],
            email: user_response['email'],
            created_at: user_response['created_at'],
            correlation_id: correlation_id,
            status: 'created'
          }
          
        when 409
          # User already exists - handle idempotency
          existing_user = get_existing_user(user_data[:email])
          
          if existing_user && user_matches?(existing_user, user_data)
            log_structured_info("Idempotent success - user already exists", {
              user_id: existing_user['id']
            })
            
            {
              user_id: existing_user['id'],
              email: existing_user['email'],
              correlation_id: correlation_id,
              status: 'already_exists'
            }
          else
            raise StandardError, "User with email #{user_data[:email]} exists with different data"
          end
          
        else
          # Let base handler deal with other HTTP responses
          handle_api_response(response, 'user_service')
        end
        
      rescue CircuitOpenError => e
        log_structured_error("Circuit breaker open for user service", { error: e.message })
        raise Tasker::RetryableError.new(e.message, retry_after: 60)
      end

      private

      def extract_user_data(context)
        {
          email: context['email'],
          name: context['name'],
          phone: context['phone'],
          plan: context['plan'] || 'free'
        }.compact
      end

      def get_existing_user(email)
        response = with_circuit_breaker('user_service') do
          http_client.get("#{user_service_url}/users", {
            query: { email: email },
            headers: default_headers,
            timeout: 15
          })
        end
        
        response.success? ? response.parsed_response : nil
      rescue => e
        log_structured_error("Failed to check existing user", { error: e.message })
        nil
      end

      def user_matches?(existing_user, new_user_data)
        existing_user['email'] == new_user_data[:email] &&
          existing_user['name'] == new_user_data[:name]
      end

      def user_service_url
        ENV.fetch('USER_SERVICE_URL', 'http://localhost:3001')
      end
    end
  end
end
```

## Distributed Tracing and Correlation

The breakthrough was implementing correlation ID tracking across all services:

```ruby
# app/concerns/circuit_breaker_pattern.rb
module CircuitBreakerPattern
  extend ActiveSupport::Concern

  class CircuitBreakerError < StandardError; end
  class CircuitOpenError < CircuitBreakerError; end

  def with_circuit_breaker(service_name)
    breaker = circuit_breaker_for(service_name)

    case breaker.state
    when :open
      raise CircuitOpenError, "Circuit breaker is OPEN for #{service_name}"
    when :half_open, :closed
      begin
        result = yield
        breaker.record_success
        result
      rescue => e
        breaker.record_failure
        raise
      end
    end
  end

  private

  def circuit_breaker_for(service_name)
    @circuit_breakers ||= {}
    @circuit_breakers[service_name] ||= CircuitBreaker.new(
      failure_threshold: 5,       # Open after 5 failures
      recovery_timeout: 60,       # Try again after 60 seconds
      success_threshold: 2        # Close after 2 successes
    )
  end
end

# Service-specific monitoring
class ServiceMonitor < Tasker::EventSubscriber::Base
  subscribe_to 'step.failed', 'step.completed'

  def handle_step_failed(event)
    if microservice_step?(event)
      service_name = extract_service_name(event[:step_name])

      # Different alerts for different failure types
      case event[:error]
      when /Circuit breaker is OPEN/
        notify_circuit_breaker_open(service_name, event)
      when /timeout/i
        notify_service_timeout(service_name, event)
      when /Rate limited/
        notify_rate_limiting(service_name, event)
      else
        notify_service_error(service_name, event)
      end
    end
  end

  def handle_step_completed(event)
    if microservice_step?(event)
      service_name = extract_service_name(event[:step_name])
      duration = event[:duration] || 0

      # Track service performance
      track_service_performance(service_name, duration)

      # Alert on slow responses
      if duration > 30_000  # 30 seconds
        notify_slow_response(service_name, duration, event)
      end
    end
  end

  private

  def microservice_step?(event)
    event[:namespace] == 'user_management'
  end

  def extract_service_name(step_name)
    case step_name
    when /user_account/
      'user_service'
    when /billing/
      'billing_service'
    when /preferences/
      'preferences_service'
    when /notification|welcome/
      'notification_service'
    else
      'unknown_service'
    end
  end
end
```

## The Results

**Before Tasker:**
- 40% user registration failure rate
- 2-4 hours to debug partial registrations
- No visibility into which service failed
- Manual cleanup scripts running daily
- Services failing independently brought down entire flows

**After Tasker:**
- 2% registration failure rate (mostly permanent failures like invalid emails)
- Automatic recovery for 90% of service hiccups
- Complete visibility into service interactions
- Circuit breakers prevent cascade failures
- Correlation IDs enable distributed debugging in minutes

## Key Takeaways

1. **Implement circuit breakers** - Prevent cascade failures when services are down

2. **Use correlation IDs** - Track requests across service boundaries for debugging

3. **Design for idempotency** - Services should handle duplicate requests gracefully

4. **Build in parallel execution** - Independent operations shouldn't wait for each other

5. **Plan for partial failures** - Know exactly what state your system is in when things fail

6. **Monitor service interactions** - Different services need different retry and alerting strategies

## Want to Try This Yourself?

The complete microservices orchestration workflow is available:

```bash
# One-line setup
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/blog-examples/microservices-coordination/setup.sh | bash

# Start all services
cd microservices-demo
docker-compose up -d  # Starts 4 simulated microservices
bundle exec sidekiq &
bundle exec rails server

# Test user registration
curl -X POST http://localhost:3000/users/register \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com", "name": "Test User", "plan": "free"}'

# Monitor the workflow across services
curl http://localhost:3000/users/registration_status/TASK_ID
```

In our next post, we'll tackle the organizational challenges that emerge as engineering teams scale: "Building Workflows That Scale With Your Team" - when namespace conflicts become your biggest problem.

---

*Have you been burned by microservices coordination failures? Share your distributed system war stories in the comments below.*
