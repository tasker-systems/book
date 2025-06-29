# Quick Start Guide: Your First Tasker Workflow

> **Build your first workflow in 15 minutes**

This guide gets you from zero to a working Tasker workflow quickly. You'll build a simple "Welcome Email" process that demonstrates core concepts like step dependencies, error handling, and result passing.

## Prerequisites

- **Rails application** (7.0+) with PostgreSQL
- **Ruby 3.2+** (required for Tasker v2.5.0)
- **PostgreSQL** (required for Tasker's high-performance SQL functions)
- **Redis** (for background job processing)
- **Basic Rails knowledge** (models, controllers, ActiveJob)

## Installation & Setup (3 minutes)

### Option 1: Automated Demo Application (Recommended)

Create a complete Tasker application with real-world workflows instantly:

```bash
# Interactive setup with full observability stack
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash

# Or specify your preferences
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-demo \
  --tasks ecommerce,inventory,customer \
  --observability \
  --non-interactive
```

### Option 2: Manual Installation (Existing Rails App)

If you have an existing Rails application:

```bash
# Add to Gemfile
echo 'gem "tasker", git: "https://github.com/tasker-systems/tasker.git", tag: "v2.5.0"' >> Gemfile

# Install and setup
bundle install
bundle exec rails tasker:install:migrations
bundle exec rails tasker:install:database_objects  # Critical step!
bundle exec rails db:migrate
bundle exec rails tasker:setup

# Mount the engine
echo 'mount Tasker::Engine, at: "/tasker"' >> config/routes.rb
```

### 3. Create a simple User model (if needed)

```bash
# Only if you don't already have a User model
rails generate model User name:string email:string
bundle exec rails db:migrate
```

## Your First Workflow: Welcome Email Process (10 minutes)

Let's create a workflow that:
1. **Validates** a user exists
2. **Generates** personalized welcome content
3. **Sends** the welcome email

### 1. Create the task handler

First, create the YAML configuration file:

```yaml
# config/tasker/tasks/welcome_user/welcome_handler.yaml
---
name: send_welcome_email
namespace_name: welcome_user
version: 1.0.0
task_handler_class: WelcomeUser::WelcomeHandler

schema:
  type: object
  required: ['user_id']
  properties:
    user_id:
      type: integer

step_templates:
  - name: validate_user
    handler_class: WelcomeUser::StepHandler::ValidateUserHandler

  - name: generate_content
    depends_on_step: validate_user
    handler_class: WelcomeUser::StepHandler::GenerateContentHandler

  - name: send_email
    depends_on_step: generate_content
    handler_class: WelcomeUser::StepHandler::SendEmailHandler
    retryable: true
    retry_limit: 3
```

Then create the task handler class:

```ruby
# app/tasks/welcome_user/welcome_handler.rb
module WelcomeUser
  class WelcomeHandler < Tasker::ConfiguredTask
    # Configuration is driven by the YAML file above
    # The class primarily handles runtime behavior and overrides

    # Optional: Custom runtime step dependency logic
    def establish_step_dependencies_and_defaults(task, steps)
      # Add runtime dependencies based on task context if needed
      if task.context['priority'] == 'urgent'
        email_step = steps.find { |s| s.name == 'send_email' }
        email_step&.update(retry_limit: 1) # Faster failure for urgent emails
      end
    end

    # Optional: Add custom annotations after completion
    def update_annotations(task, sequence, steps)
      email_results = steps.find { |s| s.name == 'send_email' }&.results
      if email_results&.dig('email_sent')
        task.annotations.create!(
          annotation_type: 'welcome_email_sent',
          content: {
            sent_to: email_results['sent_to'],
            sent_at: email_results['sent_at']
          }
        )
      end
    end
  end
end
```

### 2. Create the step handlers

**Step 1: Validate User** (`app/tasks/welcome_user/step_handler/validate_user_handler.rb`):

```ruby
module WelcomeUser
  module StepHandler
    class ValidateUserHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        user_id = task.context['user_id']

        # Find the user
        user = User.find_by(id: user_id)
        raise StandardError, "User not found: #{user_id}" unless user

        Rails.logger.info "Validated user: #{user.name} (#{user.email})"

        {
          user_id: user.id,
          user_name: user.name,
          user_email: user.email,
          validated: true
        }
      end
    end
  end
end
```

**Step 2: Generate Content** (`app/tasks/welcome_user/step_handler/generate_content_handler.rb`):

```ruby
module WelcomeUser
  module StepHandler
    class GenerateContentHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # Get user data from previous step
        validate_results = step_results(sequence, 'validate_user')
        user_name = validate_results['user_name']
        user_email = validate_results['user_email']

        # Generate personalized content
        subject = "Welcome to our platform, #{user_name}!"
        body = generate_welcome_body(user_name)

        Rails.logger.info "Generated welcome content for #{user_name}"

        {
          subject: subject,
          body: body,
          to_email: user_email,
          to_name: user_name,
          generated_at: Time.current.iso8601
        }
      end

      private

      def generate_welcome_body(name)
        <<~BODY
          Hi #{name},

          Welcome to our platform! We're excited to have you on board.

          Here are some things you can do to get started:
          • Complete your profile
          • Explore our features
          • Join our community

          If you have any questions, don't hesitate to reach out.

          Best regards,
          The Team
        BODY
      end
    end
  end
end
```

**Step 3: Send Email** (`app/tasks/welcome_user/step_handler/send_email_handler.rb`):

```ruby
module WelcomeUser
  module StepHandler
    class SendEmailHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        # Get email content from previous step
        content_results = step_results(sequence, 'generate_content')

        begin
          # Simulate email sending (replace with real email service)
          send_welcome_email(
            to: content_results['to_email'],
            name: content_results['to_name'],
            subject: content_results['subject'],
            body: content_results['body']
          )

          Rails.logger.info "Welcome email sent to #{content_results['to_email']}"

          {
            email_sent: true,
            sent_to: content_results['to_email'],
            sent_at: Time.current.iso8601
          }

        rescue Net::SMTPServerBusy => e
          # Temporary failure - will retry based on step configuration
          Rails.logger.warn "SMTP server busy, will retry: #{e.message}"
          raise e  # Let Tasker handle retries based on step configuration
        rescue Net::SMTPFatalError => e
          # Permanent failure - don't retry
          Rails.logger.error "Permanent SMTP failure: #{e.message}"
          raise StandardError, "Invalid email address: #{e.message}"
        end
      end

      private

      def send_welcome_email(to:, name:, subject:, body:)
        # For demo purposes, just log the email
        # In production, use ActionMailer or your email service
        Rails.logger.info <<~EMAIL
          📧 EMAIL SENT:
          To: #{to}
          Subject: #{subject}
          Body: #{body}
        EMAIL

        # Simulate potential SMTP delays
        sleep(0.1)
      end
    end
  end
end
```

### 3. Create some test data

```ruby
# In Rails console or db/seeds.rb
User.create!(
  name: "John Doe",
  email: "john@example.com"
)

User.create!(
  name: "Jane Smith",
  email: "jane@example.com"
)
```

## Run Your Workflow (2 minutes)

### 1. Start background job processing

```bash
# In one terminal
bundle exec sidekiq
```

### 2. Start your Rails server

```bash
# In another terminal
bundle exec rails server
```

### 3. Test your workflow

```ruby
# In Rails console
task_request = Tasker::Types::TaskRequest.new(
  name: 'send_welcome_email',
  namespace: 'welcome_user',
  version: '1.0.0',
  context: { user_id: 1 }
)

task_id = Tasker::HandlerFactory.instance.run_task(task_request)
puts "Started task: #{task_id}"

# Check status
task = Tasker::Task.find(task_id)
puts "Status: #{task.current_state}"

# View step details
task.workflow_step_sequences.last.workflow_steps.each do |step|
  puts "#{step.name}: #{step.current_state}"
  puts "  Result: #{step.results}" if step.results.present?
end

# Access via REST API (if Tasker engine is mounted)
# GET /tasker/tasks/#{task_id}
# GET /tasker/handlers/welcome_user/send_welcome_email

# Access via GraphQL (if available)
# query { task(taskId: "#{task_id}") { currentState workflowSteps { name currentState results } } }
```

### 4. Expected output

You should see logs like:
```
Validated user: John Doe (john@example.com)
Generated welcome content for John Doe
📧 EMAIL SENT:
To: john@example.com
Subject: Welcome to our platform, John Doe!
Body: Hi John Doe, Welcome to our platform!...
Welcome email sent to john@example.com
```

## What You Just Built

**🎉 Congratulations!** You've created a production-ready workflow with:

✅ **Step Dependencies**: `generate_content` waits for `validate_user`
✅ **Error Handling**: Permanent vs. retryable errors
✅ **Data Flow**: Results pass between steps
✅ **Retry Logic**: Email sending retries automatically
✅ **Logging**: Full observability into execution

## Key Concepts Demonstrated

### 1. **Task Handler** - Workflow Definition
- Defines the sequence and dependencies of steps
- Registers with a namespace and version
- Validates input schema

### 2. **Step Handlers** - Business Logic
- Each step implements one specific operation
- Returns results for dependent steps
- Handles errors appropriately

### 3. **Dependencies** - Execution Order
- `depends_on_step` ensures proper ordering
- Steps run as soon as dependencies complete
- Parallel execution when no dependencies exist

### 4. **Error Handling** - Reliability
- `RetryableError` triggers automatic retry with exponential backoff
- `PermanentError` fails immediately without retry
- Retry limits prevent infinite loops

### 5. **Result Passing** - Data Flow
- Step results are automatically persisted
- Access previous results with `step_results(sequence, 'step_name')`
- Results are available for debugging and monitoring

## Next Steps

### 🚀 Build More Complex Workflows
- Add parallel steps (multiple steps depending on the same parent)
- Create diamond patterns (multiple paths that converge)
- Add API integration steps

### 🔧 Add Production Features
- **[REST API](rest-api.md)** - HTTP API integration
- **[Authentication](authentication.md)** - Secure your workflows
- **[Event Subscribers](event-system.md)** - Add monitoring and alerting
- **[Telemetry](telemetry.md)** - OpenTelemetry spans for detailed tracing

### 📚 Explore Advanced Topics
- **[Developer Guide](developer-guide.md)** - Complete implementation guide
- **[Workflow Patterns](workflow-patterns.md)** - Common patterns and examples
- **[Real Examples](../blog/posts/post-01-ecommerce-reliability/)** - See Tasker solving real problems

## Troubleshooting

### Common Issues

**"Task handler not found"**
```bash
# Restart your Rails server to reload the new task handler
bundle exec rails server
```

**"Step handler not found"**
- Check file paths match the class names exactly
- Ensure all files are saved and the server is restarted

**"Task stays in 'pending' state"**
- Check your ActiveJob backend is running: `bundle exec sidekiq`
- Verify Redis is running: `redis-cli ping`

**"Database errors"**
- Ensure migrations have run: `bundle exec rails db:migrate`
- Check PostgreSQL is running and accessible

### Getting Help

- **[Troubleshooting Guide](troubleshooting.md)** - Comprehensive issue resolution
- **[Developer Guide](developer-guide.md)** - Detailed implementation help
- Check the logs: `tail -f log/development.log`

---

**🎉 Congratulations!** You've built your first Tasker workflow. You now understand the core concepts and are ready to build more sophisticated workflows for your application.
