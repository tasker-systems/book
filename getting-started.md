# Getting Started with Tasker

Tasker is a Rails engine that provides workflow orchestration through atomic, retryable steps. This guide introduces the core framework concepts and installation methods.

## Core Framework Concepts

### **Tasks and Steps**

- **Tasks** represent complete workflows (e.g., "process_order", "sync_data")
- **Steps** are atomic units of work within a task (e.g., "validate_cart", "charge_payment")
- **Step Dependencies** define execution order through `depends_on_step` relationships

### **YAML Configuration**

Tasks are defined declaratively in YAML files:

```yaml
# config/tasker/tasks/ecommerce/order_processing.yaml
name: process_order
namespace_name: ecommerce
version: 1.0.0

step_templates:
  - name: validate_cart
    handler_class: Ecommerce::ValidateCartHandler
  - name: process_payment
    depends_on_step: validate_cart
    handler_class: Ecommerce::ProcessPaymentHandler
    default_retryable: true
  - name: send_confirmation
    depends_on_step: process_payment
    handler_class: Ecommerce::SendConfirmationHandler
```

### **Step Handlers**

Ruby classes that implement the business logic for each step:

```ruby
class Ecommerce::ProcessPaymentHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    # Business logic here
    payment_result = PaymentService.charge(
      amount: task.context['total_amount'],
      token: task.context['payment_token']
    )

    # Error handling
    raise Tasker::PermanentError, "Card declined" if payment_result.declined?
    raise Tasker::RetryableError, "Gateway timeout" if payment_result.timeout?

    # Return step results
    { payment_id: payment_result.id, status: 'charged' }
  end
end
```

### **State Management**

- **Task States**: `pending`, `processing`, `completed`, `failed`
- **Step States**: `pending`, `processing`, `completed`, `failed`, `cancelled`
- **Retryable vs Permanent Failures**: Different error types trigger different retry behaviors

### **Event System**

Tasker publishes 56 built-in events for observability:

```ruby
class OrderTrackingSubscriber < Tasker::Events::Subscribers::BaseSubscriber
  subscribe_to 'task.completed', 'step.failed'

  def handle_task_completed(event)
    Analytics.track('order_completed', event[:context])
  end

  def handle_step_failed(event)
    NotificationService.alert("Step failed: #{event[:step_name]}")
  end
end
```

## Installation Methods

### **Quick Demo Installation**

For trying Tasker with complete demo workflows:

```bash
# With Docker (recommended for exploration)
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-demo \
  --tasks ecommerce,inventory,customer \
  --docker \
  --with-observability \
  --non-interactive

# Traditional Rails setup
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-demo \
  --tasks ecommerce,inventory,customer \
  --non-interactive
```

**[→ Try the demo workflows](./QUICK_START.md)**

### **Existing Rails Application**

To add Tasker to your existing Rails app:

#### 1. Add to Gemfile

```ruby
gem 'tasker-engine', '~> 1.0.5'
```

#### 2. Install and Setup

```bash
bundle install
bundle exec rails tasker:install:migrations
bundle exec rails tasker:install:database_objects  # Critical: installs SQL functions
bundle exec rails db:migrate
```

#### 3. Mount the Engine

```ruby
# config/routes.rb
Rails.application.routes.draw do
  mount Tasker::Engine, at: '/tasker'
  # ... your existing routes
end
```

#### 4. Configure (Optional)

```ruby
# config/initializers/tasker.rb
Tasker.configure do |config|
  config.execution.min_concurrent_steps = 2
  config.execution.max_concurrent_steps_limit = 10
  config.execution.concurrency_cache_duration = 300
end
```

## Framework Architecture

### **Rails Engine Structure**

- **Mounts at `/tasker`** in your application
- **Database tables** for tasks, steps, and execution tracking
- **SQL functions** for high-performance workflow analysis
- **Background jobs** for async step execution

### **Core Components**

#### **Task Handler**

Manages overall workflow execution:

```ruby
class Ecommerce::OrderProcessingHandler < Tasker::TaskHandler::Base
  def validate_context(context)
    # Validate required context data
  end

  def before_task_start(task)
    # Pre-execution setup
  end

  def after_task_complete(task)
    # Post-execution cleanup
  end
end
```

#### **Step Execution**

Steps run through the orchestration engine:

- **Dependency Resolution**: Determines which steps can run
- **Parallel Execution**: Independent steps run concurrently
- **Error Handling**: Retryable vs permanent failure logic
- **State Persistence**: Progress saved between executions

#### **SQL Functions**

High-performance PostgreSQL functions for:

- **Dependency Analysis**: Finding ready-to-run steps
- **State Transitions**: Atomic state updates
- **Performance Metrics**: Analytics and monitoring

## Creating Your First Workflow

### **1. Generate Task Structure**

```bash
rails generate tasker:task_handler WelcomeUser --module_namespace WelcomeUser
```

This creates:

- **Handler class**: `app/tasks/welcome_user/welcome_user_handler.rb`
- **YAML config**: `config/tasker/tasks/welcome_user/welcome_user.yaml`
- **Test file**: `spec/tasks/welcome_user/welcome_user_handler_spec.rb`

### **2. Define Step Templates**

```yaml
# config/tasker/tasks/welcome_user/welcome_user.yaml
name: welcome_user
module_namespace: WelcomeUser
task_handler_class: WelcomeUserHandler

step_templates:
  - name: validate_user
    handler_class: WelcomeUser::StepHandler::ValidateUserHandler
  - name: send_welcome_email
    depends_on_step: validate_user
    handler_class: WelcomeUser::StepHandler::SendWelcomeEmailHandler
    default_retryable: true
```

### **3. Implement Step Handlers**

```ruby
class WelcomeUser::StepHandler::ValidateUserHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    user = User.find(task.context['user_id'])
    raise Tasker::PermanentError, "User not found" unless user

    { user_email: user.email, user_name: user.name }
  end
end
```

### **4. Execute the Workflow**

```ruby
# Create and execute a task
task = Tasker::Task.create!(
  task_name: 'welcome_user',
  context: { user_id: 123 }
)

# Execute synchronously
Tasker::Orchestration::TaskOrchestrator.execute_task(task)

# Or queue for background execution
Tasker::Jobs::TaskExecutorJob.perform_later(task.task_id)
```

## Next Steps

### **Framework Exploration**

- **[Core Concepts](./docs/core-concepts.md)** - Deeper dive into framework architecture
- **[Step Handler Best Practices](./docs/STEP_HANDLER_BEST_PRACTICES.md)** - Patterns for reliable step handlers
- **[Event System](./docs/EVENT_SYSTEM.md)** - Complete event reference and custom subscribers

### **Real-World Examples**

- **[E-commerce Workflows](./blog/posts/post-01-ecommerce-reliability/)** - Order processing, inventory, payments
- **[Data Pipeline Workflows](./blog/posts/post-02-data-pipeline-resilience/)** - ETL, data validation, report generation
- **[Microservices Coordination](./blog/posts/post-03-microservices-coordination/)** - API orchestration, circuit breakers

### **Production Setup**

- **[Authentication & Authorization](./docs/AUTH.md)** - Securing workflow access
- **[Health Monitoring](./docs/HEALTH.md)** - Kubernetes-ready health checks
- **[Metrics & Observability](./docs/TELEMETRY.md)** - Prometheus, OpenTelemetry, custom metrics

---

**Ready to build reliable workflows?** Start with the [5-minute quickstart](./QUICK_START.md) to see complete examples in action.
