# Microservices Coordination: Orchestrating Complex Workflows

*Building resilient microservices workflows with Tasker's distributed coordination engine*

---

## The Challenge: Service Orchestration at Scale

Modern applications rarely exist in isolation. A simple user registration might involve coordinating with multiple services: user management, billing, preferences, notifications, and analytics. Each service has its own failure modes, response times, and availability patterns.

Traditional approaches to service orchestration often result in brittle, hard-to-maintain code with custom circuit breakers, manual retry logic, and complex state management. Tasker provides a different approach: **declarative workflow orchestration** with built-in resilience patterns.

## Real-World Scenario: User Registration Flow

Let's examine a user registration workflow that coordinates across multiple microservices:

1. **Create User Account** - UserService
2. **Setup Billing Profile** - BillingService
3. **Initialize Preferences** - PreferencesService
4. **Send Welcome Sequence** - NotificationService
5. **Update User Status** - UserService

Some steps can run in parallel (billing and preferences), while others must be sequential (welcome email after both are complete).

## Tasker's Approach: YAML-Driven Orchestration

Instead of hardcoding service calls and dependencies, Tasker uses declarative YAML configuration. This approach separates workflow structure from business logic, making complex orchestrations maintainable and testable.

The configuration supports nested input validation for complex microservices workflows:

```yaml
name: user_registration
namespace_name: blog_examples
task_handler_class: BlogExamples::Post03::UserRegistrationHandler
version: "1.0.0"
description: "Orchestrated user registration workflow across multiple microservices"
default_dependent_system: "user_management_system"

# Input validation schema
schema:
  type: object
  required: ['user_info']
  properties:
    user_info:
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
        referral_code:
          type: string
        company:
          type: string
        source:
          type: string
          enum: ['web', 'mobile', 'api']
          default: 'web'
    billing_info:
      type: object
      properties:
        payment_method:
          type: string
        billing_address:
          type: object
          properties:
            street:
              type: string
            city:
              type: string
            state:
              type: string
            zip:
              type: string
    preferences:
      type: object
      properties:
        marketing_emails:
          type: boolean
          default: false
        product_updates:
          type: boolean
          default: false
        newsletter:
          type: boolean
          default: false
    correlation_id:
      type: string
      description: "For distributed tracing"

# Step templates for service orchestration
step_templates:
  - name: create_user_account
    description: "Create user account in UserService"
    handler_class: "BlogExamples::Post03::StepHandlers::CreateUserAccountHandler"
    default_retryable: true
    default_retry_limit: 3
    handler_config:
      url: 'https://api.userservice.com'

  - name: setup_billing_profile
    description: "Create billing profile in BillingService"
    handler_class: "BlogExamples::Post03::StepHandlers::SetupBillingProfileHandler"
    depends_on_steps: ["create_user_account"]
    default_retryable: true
    default_retry_limit: 3
    handler_config:
      url: 'https://api.billingservice.com'

  - name: initialize_preferences
    description: "Set up user preferences in PreferencesService"
    handler_class: "BlogExamples::Post03::StepHandlers::InitializePreferencesHandler"
    depends_on_steps: ["create_user_account"]  # Can run parallel to billing
    default_retryable: true
    default_retry_limit: 3
    handler_config:
      url: 'https://api.preferencesservice.com'

  - name: send_welcome_sequence
    description: "Send welcome email via NotificationService"
    handler_class: "BlogExamples::Post03::StepHandlers::SendWelcomeSequenceHandler"
    depends_on_steps: ["setup_billing_profile", "initialize_preferences"]
    default_retryable: true
    default_retry_limit: 5  # Email services are often flaky
    handler_config:
      url: 'https://api.notificationservice.com'

  - name: update_user_status
    description: "Mark user registration as complete in UserService"
    handler_class: "BlogExamples::Post03::StepHandlers::UpdateUserStatusHandler"
    depends_on_steps: ["send_welcome_sequence"]
    default_retryable: true
    default_retry_limit: 2
    handler_config:
      url: 'https://api.userservice.com'

# Custom events for service monitoring (using Tasker's native circuit breaker)
custom_events:
  - name: "service_call_started"
    description: "Fired when calling external service"
  - name: "service_call_completed"
    description: "Fired when service call succeeds"
  - name: "service_call_failed"
    description: "Fired when service call fails"
```

**Key Configuration Features:**

1. **Nested Input Validation**: The schema supports complex, structured input validation with nested objects for `user_info`, `billing_info`, and `preferences`. This ensures data integrity across all microservices.

2. **Service-Specific Configuration**: Each step includes `handler_config` with service URLs, making it easy to configure different environments.

3. **Parallel Execution**: Steps like `setup_billing_profile` and `initialize_preferences` both depend only on `create_user_account`, allowing them to run in parallel.

4. **Smart Retry Policies**: Different services get different retry limits based on their reliability characteristics (email services get 5 retries, user services get 2-3).

## The Task Handler: Modern ConfiguredTask Pattern

Tasker's modern `ConfiguredTask` pattern eliminates boilerplate code by automatically handling YAML loading and step template registration. This is a significant improvement over manual configuration approaches.

**Why ConfiguredTask is Superior:**

- **Automatic YAML Loading**: No need to manually parse and load configuration files
- **Step Template Registration**: Framework automatically registers step handlers from YAML
- **Convention over Configuration**: Follows established patterns for file locations and naming
- **Reduced Complexity**: Focus on business logic instead of framework plumbing

Here's the complete task handler using the modern pattern:

```ruby
# frozen_string_literal: true

module BlogExamples
  module Post03
    # UserRegistrationHandler demonstrates YAML-driven task configuration
    # This example shows the ConfiguredTask pattern for modern Tasker applications
    class UserRegistrationHandler < Tasker::ConfiguredTask
      def self.yaml_path
        @yaml_path ||= File.join(
          File.dirname(__FILE__),
          '..', 'config', 'user_registration_handler.yaml'
        )
      end

      # Post-completion hooks
      def update_annotations(task, _sequence, steps)
        # Record service response times in task context (simplified for testing)
        service_timings = {}
        steps.each do |step|
          if step.results && step.results['service_response_time']
            service_name = step.name
            service_timings[service_name] = step.results['service_response_time']
          end
        end

        # Store in task context for testing
        task.context['service_performance'] = {
          service_timings: service_timings,
          total_duration: calculate_total_duration(steps),
          parallel_execution_saved: calculate_parallel_savings(steps)
        }

        # Record registration outcome
        task.context['registration_outcome'] = {
          user_id: steps.find { |s| s.name == 'create_user_account' }&.results&.dig('user_id'),
          plan: task.context['plan'],
          source: task.context['source'],
          completed_at: Time.current.iso8601
        }

        # Set fields expected by tests
        task.context['plan_type'] = task.context.dig('user_info', 'plan') || task.context['plan'] || 'free'
        task.context['correlation_id'] = task.context['correlation_id'] || generate_correlation_id
        task.context['registration_source'] = task.context.dig('user_info', 'source') || task.context['source'] || 'web'

        # Save the task to persist context changes
        task.save! if task.respond_to?(:save!)
      end

      private

      def generate_correlation_id
        "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
      end

      def calculate_total_duration(steps)
        return 0 unless steps.any?

        # Use created_at and updated_at since WorkflowStep doesn't have started_at
        start_time = steps.filter_map(&:created_at).min
        end_time = steps.filter_map(&:updated_at).max

        return 0 unless start_time && end_time

        ((end_time - start_time) * 1000).round(2) # Convert to milliseconds
      end

      def calculate_parallel_savings(steps)
        # Calculate how much time was saved by parallel execution
        sequential_time = steps.sum { |s| calculate_step_duration(s) }
        actual_time = calculate_total_duration(steps)

        sequential_time - actual_time
      end

      def calculate_step_duration(step)
        return 0 unless step.created_at && step.updated_at

        ((step.updated_at - step.created_at) * 1000).round(2) # Convert to milliseconds
      end
    end
  end
end
```

**What's Different from Manual Approaches:**

1. **Inherits from `Tasker::ConfiguredTask`**: Automatically gets YAML loading and step registration
2. **Simple `yaml_path` Declaration**: Just specify where the YAML file is located
3. **Focus on Business Logic**: The handler only contains workflow-specific logic like performance tracking and result aggregation
4. **No Boilerplate**: No manual step template definition or YAML parsing code

Compare this to a manual approach that would require 50+ lines of configuration parsing, step template registration, and error handling - all eliminated by the framework.

## Step Handlers: Business Logic Focus

Step handlers focus purely on business logic, with API concerns abstracted away:

```ruby
# frozen_string_literal: true

require_relative '../concerns/api_request_handling'

# CreateUserAccountHandler - Microservices Coordination Example
#
# This handler demonstrates how to coordinate with external microservices
# using Tasker's built-in circuit breaker functionality through proper error classification.
#
# KEY ARCHITECTURAL DECISIONS:
# 1. NO custom circuit breaker logic - Tasker handles this at the framework level
# 2. Focus on proper error classification (PermanentError vs RetryableError)
# 3. Let Tasker's SQL-driven retry system handle intelligent backoff and recovery
# 4. Use structured logging for observability instead of custom circuit breaker metrics
#
module BlogExamples
  module Post03
    module StepHandlers
      class CreateUserAccountHandler < Tasker::StepHandler::Api
        include BlogExamples::Post03::Concerns::ApiRequestHandling

        def process(task, sequence, step)
          set_current_context(task, step, sequence)

          # Extract and validate all required inputs
          user_inputs = extract_and_validate_inputs(task, sequence, step)

          Rails.logger.info "Creating user account for #{user_inputs[:email]}"

          # Create user account through microservice
          # Tasker's circuit breaker logic is handled automatically through error classification
          create_user_account(user_inputs)
        rescue StandardError => e
          Rails.logger.error "User account creation failed: #{e.message}"
          raise
        end

        # Override process_results to set business logic results based on response
        def process_results(step, service_response, _initial_results)
          # Set business logic results based on response status
          case service_response.status
          when 201
            step.results = process_successful_creation(service_response)
          when 409
            # For 409, we need to check if it's idempotent
            user_inputs = extract_and_validate_inputs(@current_task, @current_sequence, step)
            step.results = process_existing_user(user_inputs, service_response)
          else
            # For other statuses, let the framework handle the error
            # The ResponseProcessor will raise appropriate errors
            step.results = {
              error: true,
              status_code: service_response.status,
              response_body: service_response.body
            }
          end
        end

        private

        # Extract and validate all required inputs for user account creation
        def extract_and_validate_inputs(task, _sequence, _step)
          # Normalize all hash keys to symbols for consistent access
          context = task.context.deep_symbolize_keys
          user_info = context[:user_info] || {}

          # Validate required fields - these are PERMANENT errors (don't retry)
          unless user_info[:email]
            raise Tasker::PermanentError.new(
              'Email is required but was not provided',
              error_code: 'MISSING_EMAIL'
            )
          end

          unless user_info[:name]
            raise Tasker::PermanentError.new(
              'Name is required but was not provided',
              error_code: 'MISSING_NAME'
            )
          end

          # Build validated user data with defaults
          {
            email: user_info[:email],
            name: user_info[:name],
            phone: user_info[:phone],
            plan: user_info[:plan] || 'free',
            marketing_consent: context[:preferences]&.dig(:marketing_emails) || false,
            referral_code: user_info[:referral_code],
            source: user_info[:source] || 'web'
          }.compact
        end

        # Create user account using validated inputs
        def create_user_account(user_inputs)
          start_time = Time.current

          log_api_call(:post, 'user_service/users', timeout: 30)

          # Call the mock service - demonstrates Tasker's circuit breaker through error classification
          user_service = get_service(:user_service)
          response = user_service.create_user(user_inputs)

          duration_ms = ((Time.current - start_time) * 1000).to_i
          log_api_response(:post, 'user_service/users', response, duration_ms)

          # Return the original response for framework processing
          response
        end

        # Process successful user creation response
        def process_successful_creation(response)
          user_response = response.body.deep_symbolize_keys

          # Validate the response structure
          ensure_user_creation_successful!(user_response)

          Rails.logger.info "User account created successfully: #{user_response[:id]}"

          # Return structured results for the next step
          {
            user_id: user_response[:id],
            email: user_response[:email],
            created_at: user_response[:created_at],
            correlation_id: correlation_id,
            service_response_time: response.headers['x-response-time'],
            status: 'created'
          }
        end

        # Process existing user with idempotency check
        def process_existing_user(user_inputs, _response)
          Rails.logger.info "User already exists, checking for idempotency: #{user_inputs[:email]}"

          existing_user = get_existing_user(user_inputs[:email])

          if existing_user && user_matches?(existing_user, user_inputs)
            Rails.logger.info "Existing user matches, treating as idempotent success: #{existing_user[:id]}"

            {
              user_id: existing_user[:id],
              email: existing_user[:email],
              created_at: existing_user[:created_at],
              correlation_id: correlation_id,
              status: 'already_exists'
            }
          else
            raise Tasker::PermanentError.new(
              "User with email #{user_inputs[:email]} already exists with different data",
              error_code: 'USER_CONFLICT'
            )
          end
        end

        # Get existing user for idempotency check
        def get_existing_user(email)
          # Tasker's retry system will handle failures automatically
          user_service = get_service(:user_service)
          response = user_service.get_user_by_email(email)

          response.success? ? response.body.deep_symbolize_keys : nil
        rescue Tasker::PermanentError => e
          # Don't retry permanent failures (like 404s)
          Rails.logger.error "Permanent error checking existing user: #{e.message}"
          nil
        rescue StandardError => e
          # Re-raise other errors for Tasker's retry system to handle
          Rails.logger.error "Failed to check existing user: #{e.message}"
          raise
        end

        # Check if existing user matches new user data for idempotency
        def user_matches?(existing_user, new_user_data)
          # Check if core attributes match for idempotency
          existing_user &&
            existing_user[:email] == new_user_data[:email] &&
            existing_user[:name] == new_user_data[:name] &&
            existing_user[:plan] == new_user_data[:plan]
        end

        # Ensure user creation was successful
        def ensure_user_creation_successful!(user_response)
          unless user_response[:id]
            raise Tasker::PermanentError.new(
              'User creation appeared successful but no user ID was returned',
              error_code: 'MISSING_USER_ID_IN_RESPONSE'
            )
          end

          return if user_response[:email]

          raise Tasker::PermanentError.new(
            'User creation appeared successful but no email was returned',
            error_code: 'MISSING_EMAIL_IN_RESPONSE'
          )
        end
      end
    end
  end
end
```

## API Request Handling: Abstracted Concerns

The API handling logic is cleanly separated into a reusable concern:

```ruby
# frozen_string_literal: true

# API Request Handling for Microservices Coordination
#
# This concern demonstrates how to handle API requests in a microservices architecture
# using Tasker's built-in circuit breaker functionality through proper error classification.
#
# KEY INSIGHT: Tasker provides superior circuit breaker functionality through its
# SQL-driven retry architecture. Custom circuit breaker patterns are unnecessary and
# actually work against Tasker's distributed coordination capabilities.
#
module BlogExamples
  module Post03
    module Concerns
      module ApiRequestHandling
        extend ActiveSupport::Concern

        included do
          # Initialize with mock service access for blog examples
          def initialize(*args, **kwargs)
            # For blog examples, provide a dummy URL to satisfy Api::Config requirements
            # since we use mock services instead of real HTTP requests
            dummy_config = Tasker::StepHandler::Api::Config.new(url: 'http://localhost:3000')
            kwargs[:config] ||= dummy_config

            super
            @mock_services = {
              user_service: BlogExamples::MockServices::MockUserService.new,
              billing_service: BlogExamples::MockServices::MockBillingService.new,
              preferences_service: BlogExamples::MockServices::MockPreferencesService.new,
              notification_service: BlogExamples::MockServices::MockNotificationService.new
            }
          end
        end

        protected

        # Get mock service by name (business logic, not framework)
        def get_service(service_name)
          @mock_services[service_name.to_sym] || raise("Unknown service: #{service_name}")
        end

        # Enhanced response handler leveraging Tasker's error classification
        # This is where Tasker's circuit breaker logic is implemented - through error types!
        def handle_microservice_response(response, service_name)
          case response.status
          when 200..299
            # Success - circuit breaker records success automatically
            response.body

          when 400, 422
            # Client errors - PERMANENT failures
            # Tasker's circuit breaker will NOT retry these (circuit stays "open" indefinitely)
            raise Tasker::PermanentError.new(
              "#{service_name} validation error: #{response.body}",
              error_code: 'CLIENT_VALIDATION_ERROR',
              context: { service: service_name, status: response.status }
            )

          when 401, 403
            # Authentication/authorization errors - PERMANENT failures
            raise Tasker::PermanentError.new(
              "#{service_name} authentication failed: #{response.status}",
              error_code: 'AUTH_ERROR',
              context: { service: service_name }
            )

          when 404
            # Not found - usually PERMANENT, but depends on context
            raise Tasker::PermanentError.new(
              "#{service_name} resource not found",
              error_code: 'RESOURCE_NOT_FOUND',
              context: { service: service_name }
            )

          when 409
            # Conflict - resource already exists, typically idempotent success
            response.body

          when 429
            # Rate limiting - RETRYABLE with server-specified backoff
            # This is where Tasker's intelligent backoff shines!
            retry_after = response.headers['retry-after']&.to_i || 60
            raise Tasker::RetryableError.new(
              "#{service_name} rate limited",
              retry_after: retry_after,
              context: { service: service_name, rate_limit_type: 'server_requested' }
            )

          when 500..599
            # Server errors - RETRYABLE with exponential backoff
            # Tasker's circuit breaker will handle intelligent retry timing
            raise Tasker::RetryableError.new(
              "#{service_name} server error: #{response.status}",
              context: {
                service: service_name,
                status: response.status,
                error_type: 'server_error'
              }
            )

          else
            # Unknown status codes - treat as retryable to be safe
            raise Tasker::RetryableError.new(
              "#{service_name} unknown error: #{response.status}",
              context: { service: service_name, status: response.status }
            )
          end
        end

        # Correlation ID generation for distributed tracing
        def correlation_id
          @correlation_id ||= @current_task&.context&.dig('correlation_id') || generate_correlation_id
        end

        def generate_correlation_id
          "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
        end

        # Business logic helper methods
        def step_results(sequence, step_name)
          step = sequence.steps.find { |s| s.name == step_name }
          step&.results || {}
        end

        def log_api_call(method, url, options = {})
          log_structured(:info, 'API call initiated', {
                           method: method.to_s.upcase,
                           url: url,
                           service: extract_service_name(url),
                           timeout: options[:timeout]
                         })
        end

        def log_api_response(method, url, response, duration_ms)
          status = response.respond_to?(:status) ? response.status : response.code

          # Handle response body - convert to JSON string if it's a Hash
          body = response.respond_to?(:body) ? response.body : response.body
          body_size = if body.is_a?(Hash)
                        body.to_json.bytesize
                      elsif body.respond_to?(:bytesize)
                        body.bytesize
                      else
                        body.to_s.bytesize
                      end

          log_structured(:info, 'API call completed', {
                           method: method.to_s.upcase,
                           url: url,
                           service: extract_service_name(url),
                           status_code: status,
                           duration_ms: duration_ms,
                           response_size: body_size
                         })
        end

        def log_structured(level, message, context = {})
          full_context = {
            message: message,
            correlation_id: correlation_id,
            step_name: @current_step&.name,
            task_id: @current_task&.id,
            timestamp: Time.current.iso8601
          }.merge(context)

          puts "[#{level.upcase}] #{full_context.to_json}" if Rails.env.test?
        end

        def extract_service_name(url)
          uri = URI.parse(url)
          # Extract service name from hostname or path
          if uri.hostname&.include?('localhost')
            # Local development - extract from port or path
            case uri.port
            when 3001
              'user_service'
            when 3002
              'billing_service'
            when 3003
              'preferences_service'
            when 3004
              'notification_service'
            else
              uri.path.split('/')[1] || 'unknown_service'
            end
          else
            # Production - extract from subdomain or hostname
            uri.hostname&.split('.')&.first || 'unknown_service'
          end
        end

        # Convenience methods for step handlers to set context
        def set_current_context(task, step, sequence = nil)
          @current_task = task
          @current_step = step
          @current_sequence = sequence
        end
      end
    end
  end
end
```

## Key Architectural Insights

### 1. **Modern ConfiguredTask Pattern**
Tasker's `ConfiguredTask` automatically handles YAML loading and step template registration, eliminating boilerplate code.

### 2. **No Custom Circuit Breakers**
Tasker's SQL-driven retry system provides superior circuit breaker functionality. Custom implementations often work against the framework's distributed coordination capabilities.

### 3. **Error Classification is Circuit Breaking**
The key to Tasker's circuit breaker is proper error classification:
- `PermanentError` - Circuit stays "open" indefinitely (no retries)
- `RetryableError` - Circuit uses intelligent backoff and recovery

### 4. **Separation of Concerns**
- **Task Handler**: Business logic, validation, orchestration
- **Step Handlers**: Domain-specific processing
- **API Concerns**: Reusable HTTP handling, error classification

### 5. **Declarative Dependencies**
YAML configuration makes complex dependencies explicit and maintainable:
```yaml
depends_on_steps: ["setup_billing_profile", "initialize_preferences"]
```

### 6. **Structured Input Validation**
The YAML schema supports nested objects for complex workflows, which is crucial for microservices coordination where different services need different data structures:

```yaml
user_info:
  required: ['email', 'name']
  properties:
    plan:
      enum: ['free', 'pro', 'enterprise']
billing_info:
  properties:
    payment_method: string
    billing_address:
      type: object
preferences:
  properties:
    marketing_emails: boolean
```

This nested approach provides several benefits:

- **Service Isolation**: Each service gets only the data it needs (`user_info` for UserService, `billing_info` for BillingService)
- **Type Safety**: JSON Schema validation ensures data types are correct before any service calls
- **Default Values**: Sensible defaults reduce the chance of missing required fields
- **Documentation**: The schema serves as living documentation of what each service expects

## Testing the Implementation

The complete implementation includes comprehensive tests that validate:

```bash
# Run the microservices coordination tests
cd /Users/petetaylor/projects/tasker
bundle exec rspec spec/blog/post_03_microservices_coordination/
```

## Production Considerations

### 1. **Service Discovery**
In production, replace mock services with actual service discovery:
```ruby
def get_service(service_name)
  ServiceRegistry.get_client(service_name)
end
```

### 2. **Configuration Management**
Use environment-specific configuration:
```yaml
handler_config:
  url: <%= ENV['USER_SERVICE_URL'] %>
```

### 3. **Monitoring and Observability**
Tasker provides built-in metrics for service coordination:
- Service call success/failure rates
- Response time distributions
- Circuit breaker state changes
- Parallel execution efficiency

## Next Steps

The [complete implementation](https://github.com/tasker-systems/tasker/tree/main/spec/blog/fixtures/post_03_microservices_coordination) demonstrates production-ready patterns for:

- **Idempotency handling** for reliable service coordination
- **Correlation ID propagation** for distributed tracing
- **Structured logging** for operational visibility
- **Error classification** for intelligent retry behavior

In our next post, we'll explore how these patterns scale when coordinating teams and processes, not just services.

---

*This post is part of our series on building resilient systems with Tasker. The complete source code and tests are available in the [Tasker repository](https://github.com/tasker-systems/tasker/tree/main/spec/blog/).*
