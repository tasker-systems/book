# Tasker Documentation

Quick reference to official Tasker documentation and resources.

## 📚 Core Documentation

### Getting Started
- **[Quick Start Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/QUICK_START.md)**: Build your first workflow in 15 minutes
- **[Installation Guide](https://github.com/jcoletaylor/tasker/blob/main/README.md#installation)**: Complete setup instructions
- **[System Overview](https://github.com/jcoletaylor/tasker/blob/main/docs/OVERVIEW.md)**: Architecture and key concepts

### Developer Guides
- **[Developer Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/DEVELOPER_GUIDE.md)**: Comprehensive implementation guide
- **[Task Handler Patterns](https://github.com/jcoletaylor/tasker/blob/main/docs/TASK_PATTERNS.md)**: Common workflow designs
- **[Step Handler Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/STEP_HANDLERS.md)**: Individual step implementation

### Advanced Topics
- **[Event System](https://github.com/jcoletaylor/tasker/blob/main/docs/EVENT_SYSTEM.md)**: Observability and integrations
- **[Registry Systems](https://github.com/jcoletaylor/tasker/blob/main/docs/REGISTRY_SYSTEMS.md)**: Handler organization and discovery
- **[API Documentation](https://github.com/jcoletaylor/tasker/blob/main/docs/REST_API.md)**: Complete REST API reference

## 🏗️ Architecture Reference

### Core Components

| Component | Purpose | Documentation |
|-----------|---------|---------------|
| **TaskHandler** | Workflow definition and coordination | [Developer Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/DEVELOPER_GUIDE.md#task-handlers) |
| **StepHandler** | Individual step implementation | [Step Handler Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/STEP_HANDLERS.md) |
| **WorkflowStep** | Step execution and state management | [System Overview](https://github.com/jcoletaylor/tasker/blob/main/docs/OVERVIEW.md#workflow-steps) |
| **EventSystem** | Observability and monitoring | [Event System](https://github.com/jcoletaylor/tasker/blob/main/docs/EVENT_SYSTEM.md) |
| **RegistrySystem** | Handler organization and discovery | [Registry Systems](https://github.com/jcoletaylor/tasker/blob/main/docs/REGISTRY_SYSTEMS.md) |

### Key Concepts

#### Workflows and Dependencies
```ruby
# Task handlers define step sequences and dependencies
define_step_templates do |templates|
  templates.define(
    name: 'validate_input',
    handler_class: 'MyApp::ValidateInputHandler'
  )
  templates.define(
    name: 'process_data',
    depends_on_step: 'validate_input',  # Dependency management
    handler_class: 'MyApp::ProcessDataHandler'
  )
end
```

#### Retry Logic and Error Handling
```ruby
# Intelligent retry strategies
templates.define(
  name: 'external_api_call',
  retryable: true,
  retry_limit: 3,
  timeout: 30.seconds,
  handler_class: 'MyApp::ApiCallHandler'
)

# Step handlers distinguish error types
def process(task, sequence, step)
  result = external_service.call
rescue NetworkTimeoutError => e
  raise Tasker::RetryableError, "Service timeout: #{e.message}"
rescue InvalidDataError => e
  raise Tasker::NonRetryableError, "Bad data: #{e.message}"
end
```

#### Namespaces and Versioning
```ruby
# Organize workflows by domain and version
task_request = Tasker::Types::TaskRequest.new(
  name: 'process_order',
  namespace: 'ecommerce',
  version: '2.1.0',
  context: { order_id: 123 }
)
```

## 🔧 Production Features

### Authentication & Authorization
- **[Auth Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/AUTH.md)**: JWT integration and role-based permissions
- **[Security](https://github.com/jcoletaylor/tasker/blob/main/docs/SECURITY.md)**: Enterprise security patterns

### Observability & Monitoring
- **[Telemetry](https://github.com/jcoletaylor/tasker/blob/main/docs/TELEMETRY.md)**: OpenTelemetry integration
- **[Metrics](https://github.com/jcoletaylor/tasker/blob/main/docs/METRICS.md)**: Prometheus metrics collection
- **[Health Monitoring](https://github.com/jcoletaylor/tasker/blob/main/docs/HEALTH.md)**: Kubernetes-ready health endpoints

### Performance & Scaling
- **[SQL Functions](https://github.com/jcoletaylor/tasker/blob/main/docs/SQL_FUNCTIONS.md)**: High-performance workflow execution
- **[Performance Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/PERFORMANCE.md)**: Optimization techniques

## 🧪 Testing and Development

### Testing Patterns
- **[Testing Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/TESTING.md)**: Comprehensive testing strategies
- **[Test Helpers](https://github.com/jcoletaylor/tasker/blob/main/docs/TEST_HELPERS.md)**: Built-in testing utilities

### Development Tools
- **[Generators](https://github.com/jcoletaylor/tasker/blob/main/docs/GENERATORS.md)**: Rails generators for rapid development
- **[Debugging](https://github.com/jcoletaylor/tasker/blob/main/docs/DEBUGGING.md)**: Troubleshooting workflow issues

## 📊 Examples and Patterns

### Real-World Examples
- **[Spec Examples](https://github.com/jcoletaylor/tasker/tree/main/spec/examples)**: Complete workflow implementations
- **[Demo Applications](https://github.com/jcoletaylor/tasker/tree/main/spec/dummy)**: Full Rails application examples

### Common Patterns
- **[Linear Workflows](https://github.com/jcoletaylor/tasker/blob/main/docs/patterns/linear.md)**: Sequential step execution
- **[Parallel Workflows](https://github.com/jcoletaylor/tasker/blob/main/docs/patterns/parallel.md)**: Concurrent step execution
- **[Diamond Patterns](https://github.com/jcoletaylor/tasker/blob/main/docs/patterns/diamond.md)**: Fan-out and fan-in workflows
- **[Tree Patterns](https://github.com/jcoletaylor/tasker/blob/main/docs/patterns/tree.md)**: Complex dependency graphs

## 🔗 API Reference

### REST API
- **[OpenAPI Specification](https://github.com/jcoletaylor/tasker/blob/main/docs/openapi.yml)**: Complete API documentation
- **[Handler Discovery](https://github.com/jcoletaylor/tasker/blob/main/docs/REST_API.md#handler-discovery)**: Dynamic workflow discovery
- **[Task Management](https://github.com/jcoletaylor/tasker/blob/main/docs/REST_API.md#task-management)**: CRUD operations for tasks

### GraphQL API
- **[GraphQL Schema](https://github.com/jcoletaylor/tasker/blob/main/docs/GRAPHQL.md)**: Complete schema documentation
- **[Subscriptions](https://github.com/jcoletaylor/tasker/blob/main/docs/GRAPHQL.md#subscriptions)**: Real-time workflow updates

### Ruby API
- **[API Documentation](https://rubydoc.info/github/jcoletaylor/tasker)**: Complete Ruby API reference
- **[Core Classes](https://github.com/jcoletaylor/tasker/blob/main/docs/API_REFERENCE.md)**: Main classes and methods

## 🛠️ Configuration Reference

### Engine Configuration
```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  # Basic configuration
  config.enabled = true
  config.namespace = 'my_app'
  
  # Database configuration
  config.database do |db|
    db.pool_size = 25
    db.timeout = 30
  end
  
  # Authentication configuration
  config.auth do |auth|
    auth.provider = :jwt
    auth.jwt_secret = Rails.application.credentials.tasker_jwt_secret
  end
  
  # Telemetry configuration
  config.telemetry do |t|
    t.enabled = true
    t.exporter = :otlp
    t.endpoint = 'http://jaeger:14268/api/traces'
  end
end
```

### YAML Configuration
```yaml
# config/tasker/tasks/my_namespace/my_task.yaml
name: my_namespace/my_task
namespace_name: my_namespace
version: 1.0.0
description: "Example task configuration"

schema:
  type: object
  required: [user_id]
  properties:
    user_id:
      type: integer

step_templates:
  - name: validate_user
    handler_class: MyNamespace::StepHandlers::ValidateUserHandler
    retryable: true
    retry_limit: 3
    
  - name: process_request
    depends_on_step: validate_user
    handler_class: MyNamespace::StepHandlers::ProcessRequestHandler
```

## 📈 Migration and Upgrade Guides

### Version Migration
- **[Migration Guide](https://github.com/jcoletaylor/tasker/blob/main/docs/MIGRATION.md)**: Upgrading between versions
- **[Breaking Changes](https://github.com/jcoletaylor/tasker/blob/main/CHANGELOG.md)**: Version-specific changes

### From Other Systems
- **[From Sidekiq-Cron](https://github.com/jcoletaylor/tasker/blob/main/docs/migrations/sidekiq-cron.md)**: Migrating scheduled jobs
- **[From DelayedJob](https://github.com/jcoletaylor/tasker/blob/main/docs/migrations/delayed-job.md)**: Migrating background jobs
- **[From Custom Solutions](https://github.com/jcoletaylor/tasker/blob/main/docs/migrations/custom.md)**: Replacing homegrown workflow systems

## 🤝 Community Resources

### Contributing
- **[Contributing Guide](https://github.com/jcoletaylor/tasker/blob/main/CONTRIBUTING.md)**: How to contribute to Tasker
- **[Development Setup](https://github.com/jcoletaylor/tasker/blob/main/docs/DEVELOPMENT.md)**: Setting up development environment
- **[Code of Conduct](https://github.com/jcoletaylor/tasker/blob/main/CODE_OF_CONDUCT.md)**: Community guidelines

### Support Channels
- **[GitHub Issues](https://github.com/jcoletaylor/tasker/issues)**: Bug reports and feature requests
- **[GitHub Discussions](https://github.com/jcoletaylor/tasker/discussions)**: Community questions and discussions
- **[Wiki](https://github.com/jcoletaylor/tasker/wiki)**: Community-contributed patterns and tips

## 📋 Quick Reference Cards

### Task Handler Template
```ruby
module MyNamespace
  class MyTaskHandler < Tasker::TaskHandler::Base
    TASK_NAME = 'my_task'
    NAMESPACE = 'my_namespace'
    VERSION = '1.0.0'
    
    register_handler(TASK_NAME, namespace_name: NAMESPACE, version: VERSION)
    
    define_step_templates do |templates|
      templates.define(
        name: 'step_one',
        handler_class: 'MyNamespace::StepHandlers::StepOneHandler'
      )
    end
    
    def schema
      {
        type: 'object',
        required: ['input_data'],
        properties: {
          input_data: { type: 'string' }
        }
      }
    end
  end
end
```

### Step Handler Template
```ruby
module MyNamespace
  module StepHandlers
    class StepOneHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        input_data = task.context['input_data']
        
        # Process the data
        result = perform_work(input_data)
        
        # Return results for next steps
        {
          processed_data: result,
          timestamp: Time.current.iso8601
        }
      rescue ExternalServiceError => e
        raise Tasker::RetryableError, "Service unavailable: #{e.message}"
      rescue ValidationError => e
        raise Tasker::NonRetryableError, "Invalid input: #{e.message}"
      end
      
      private
      
      def perform_work(data)
        # Implementation here
      end
    end
  end
end
```

### Task Execution
```ruby
# Create and execute a task
task_request = Tasker::Types::TaskRequest.new(
  name: 'my_task',
  namespace: 'my_namespace',
  version: '1.0.0',
  context: { input_data: 'example' }
)

# Asynchronous execution
task = Tasker::TaskExecutor.execute_async(task_request)

# Synchronous execution
task = Tasker::TaskExecutor.execute_sync(task_request)

# Check status
puts task.status  # 'pending', 'running', 'completed', 'failed'

# Get results
task.workflow_steps.each do |step|
  puts "#{step.name}: #{step.status} - #{step.result}"
end
```

---

*For the most up-to-date documentation, always check the [official Tasker repository](https://github.com/jcoletaylor/tasker).*
