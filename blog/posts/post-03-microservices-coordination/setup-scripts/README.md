# Microservices Coordination - Setup Scripts

This directory contains scripts to quickly set up and test the microservices coordination examples from Chapter 3.

## 🚀 Quick Start

### One-Command Setup (Recommended)
The fastest way to try the example with zero local dependencies:

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_03_microservices_coordination/setup-scripts/blog-setup.sh | bash

# Or with custom app name
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_03_microservices_coordination/setup-scripts/blog-setup.sh | bash -s -- --app-name my-microservices-demo
```

**Requirements:** Docker and Docker Compose only

### Local Setup
If you prefer to run the setup script locally:

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_03_microservices_coordination/setup-scripts/blog-setup.sh -o blog-setup.sh
chmod +x blog-setup.sh

# Run with options
./blog-setup.sh --app-name microservices-demo --output-dir ./demos
```

## 🛠️ How It Works

### Docker-Based Architecture
The setup script creates a complete Docker environment with:

- **Rails application** with live code reloading
- **PostgreSQL 15** database
- **Redis 7** for background job processing
- **Sidekiq** for workflow execution
- **All tested code examples** from the GitHub repository

### Integration with Tasker Repository
All code examples are downloaded directly from the tested repository:

```bash
# Task handler from tested examples
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/fixtures/post_03_microservices_coordination/task_handler/create_user_account_handler.rb

# Step handlers from tested examples
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/fixtures/post_03_microservices_coordination/step_handlers/validate_user_info_handler.rb

# API concerns from tested examples
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/fixtures/post_03_microservices_coordination/concerns/user_service_api.rb
```

This ensures the examples are always up-to-date and have passed integration tests.

## 📋 What Gets Created

### Application Structure
```
microservices-demo/
├── docker-compose.yml                          # Docker services configuration
├── Dockerfile                                  # Application container
├── app/
│   ├── tasks/user_onboarding/
│   │   ├── create_user_account_handler.rb     # Main workflow handler
│   │   └── step_handlers/
│   │       ├── validate_user_info_handler.rb  # User validation
│   │       ├── setup_billing_handler.rb       # Billing setup
│   │       └── configure_preferences_handler.rb # Preferences setup
│   ├── concerns/api_handling/
│   │   ├── user_service_api.rb                # User service integration
│   │   ├── billing_service_api.rb             # Billing service integration
│   │   └── notification_service_api.rb        # Notification service integration
│   └── controllers/
│       └── user_onboarding_controller.rb      # REST API endpoints
├── config/tasker/tasks/
│   └── create_user_account_handler.yaml       # Workflow configuration
└── spec/integration/
    └── user_onboarding_workflow_spec.rb       # Integration tests
```

### API Endpoints
- `POST /user_onboarding` - Start user onboarding workflow
- `GET /user_onboarding/status/:task_id` - Monitor onboarding progress
- `GET /user_onboarding/results/:task_id` - Get onboarding results

## 🧪 Testing the Microservices Coordination

### Start the Application
```bash
cd microservices-demo
docker-compose up
```

Wait for all services to be ready (you'll see "Ready for connections" messages).

### Create New User Account
```bash
curl -X POST http://localhost:3000/user_onboarding \
  -H 'Content-Type: application/json' \
  -d '{
    "user_onboarding": {
      "user_info": {
        "email": "test@example.com",
        "first_name": "John",
        "last_name": "Doe",
        "phone": "+1234567890"
      },
      "billing_info": {
        "plan_type": "premium",
        "payment_method": "credit_card",
        "billing_address": "123 Main St"
      },
      "preferences": {
        "newsletter_opt_in": true,
        "sms_notifications": false,
        "data_sharing_consent": true
      }
    }
  }'
```

### Monitor Onboarding Progress
```bash
# Replace TASK_ID with the actual task ID from the response
curl http://localhost:3000/user_onboarding/status/TASK_ID
```

### Get Onboarding Results
```bash
curl http://localhost:3000/user_onboarding/results/TASK_ID
```

### Test with Different Plan Types
```bash
curl -X POST http://localhost:3000/user_onboarding \
  -H 'Content-Type: application/json' \
  -d '{
    "user_onboarding": {
      "user_info": {
        "email": "enterprise@example.com",
        "first_name": "Jane",
        "last_name": "Smith"
      },
      "billing_info": {
        "plan_type": "enterprise",
        "payment_method": "invoice"
      },
      "preferences": {
        "newsletter_opt_in": false,
        "sms_notifications": true
      }
    }
  }'
```

## 🔧 Key Features Demonstrated

### Service Orchestration
The workflow demonstrates coordination across multiple services:
- User service for account creation
- Billing service for payment setup
- Notification service for welcome emails
- Each service has its own retry and timeout policies

### Circuit Breaker Pattern
Built-in resilience against service failures:
- Automatic retry for transient failures
- Circuit breaker prevents cascading failures
- Graceful degradation when services are unavailable

### Structured Input Validation
Comprehensive validation of complex nested data:
- User information validation (email, phone, names)
- Billing information validation (plan types, payment methods)
- Preferences validation (consent, notification settings)
- Type safety and schema enforcement

### API Abstraction
Clean separation between business logic and API handling:
- Step handlers focus on business logic
- API concerns handle service integration
- Consistent error handling across services
- Correlation ID tracking for distributed tracing

### Idempotency Handling
Safe retry of operations:
- Duplicate detection for user creation
- Idempotent billing setup
- Safe preference updates

## 🔍 Monitoring and Observability

### Docker Logs
```bash
# View all service logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f web
docker-compose logs -f sidekiq
```

### Workflow Monitoring
```bash
# Check running workflows
curl http://localhost:3000/user_onboarding/status/TASK_ID

# View detailed step information
docker-compose exec web rails console
# Then: Tasker::Task.find('task_id').workflow_step_sequences.last.steps
```

### Service Health Tracking
Each step provides service-specific information:
- Which service was called
- Response times and status codes
- Retry attempts and failure reasons
- Correlation IDs for distributed tracing

## 🛠️ Customization

### Adding New Services
1. Create a new API concern for the service
2. Create a step handler that uses the concern
3. Add the step to the YAML configuration

Example:
```ruby
# Create app/concerns/api_handling/analytics_service_api.rb
module ApiHandling::AnalyticsServiceApi
  extend ActiveSupport::Concern

  def track_user_signup(user_data)
    correlation_id = SecureRandom.uuid

    response = HTTParty.post(
      "#{analytics_service_url}/events",
      body: {
        event_type: 'user_signup',
        user_data: user_data,
        correlation_id: correlation_id
      }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )

    handle_analytics_response(response, correlation_id)
  end
end
```

### Modifying Service Behavior
Update the API concerns to change service interaction:

```ruby
# In app/concerns/api_handling/user_service_api.rb
def create_user_account(user_info)
  # Add custom validation
  validate_email_domain(user_info[:email])

  # Add custom headers
  headers = {
    'Content-Type' => 'application/json',
    'X-Client-Version' => '1.0.0'
  }

  # Make the API call
  response = HTTParty.post(user_service_url, body: user_info.to_json, headers: headers)
  handle_user_service_response(response)
end
```

### Adjusting Retry Policies
Update the YAML configuration for different services:

```yaml
# In config/tasker/tasks/create_user_account_handler.yaml
step_templates:
  - name: validate_user_info
    retryable: true
    retry_limit: 2  # User validation shouldn't need many retries
    timeout: 5000   # 5 second timeout

  - name: setup_billing
    retryable: true
    retry_limit: 5  # Billing service can be flaky
    timeout: 15000  # 15 second timeout
```

## 🔧 Troubleshooting

### Common Issues

**Docker services won't start:**
- Ensure Docker is running: `docker --version`
- Check for port conflicts: `docker-compose ps`
- Free up resources: `docker system prune`

**Workflow doesn't start:**
- Ensure all services are healthy: `docker-compose ps`
- Check Sidekiq is running: `docker-compose logs sidekiq`
- Verify database is ready: `docker-compose exec web rails db:migrate:status`

**Service calls fail:**
- Check network connectivity between containers
- Verify service URLs in the API concerns
- Review correlation IDs in logs for distributed tracing
- Check for authentication or authorization issues

**Steps fail with validation errors:**
- Verify input data matches the YAML schema
- Check for required fields in nested objects
- Ensure data types match expectations (strings, booleans, etc.)

### Getting Help

1. **Check service status**: `docker-compose ps`
2. **View logs**: `docker-compose logs -f`
3. **Restart services**: `docker-compose restart`
4. **Clean restart**: `docker-compose down && docker-compose up`

## 🔮 Related Examples

- **Chapter 1**: [E-commerce Reliability](../../post-01-ecommerce-reliability/setup-scripts/) - Foundation patterns
- **Chapter 2**: [Data Pipeline Resilience](../../post-02-data-pipeline-resilience/setup-scripts/) - Batch processing patterns

## 📖 Learn More

- **Blog Post**: [When Your Microservices Became a Distributed Monolith](../blog-post.md)
- **Code Examples**: [GitHub Repository](https://github.com/tasker-systems/tasker/tree/main/spec/blog/fixtures/post_03_microservices_coordination)
- **Integration Tests**: See how the examples are tested in the repository

## 🛑 Cleanup

When you're done experimenting:

```bash
# Stop all services
docker-compose down

# Remove all containers and volumes
docker-compose down -v

# Remove downloaded images (optional)
docker image prune
```

## 💡 Next Steps

Once you have the workflow running:

1. **Experiment with service failures** - Simulate network timeouts and service unavailability
2. **Customize the business logic** - Add new validation rules or service integrations
3. **Add new services** - Extend with additional microservices
4. **Implement real integrations** - Replace mock services with real APIs
5. **Scale the coordination** - Test with multiple concurrent workflows

The patterns demonstrated here scale from simple service orchestration to complex distributed systems with dozens of microservices.
