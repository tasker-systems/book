# Quick Start Guide: Your First Tasker Workflow

> **Build your first workflow in 15 minutes**

This guide gets you from zero to a working Tasker workflow quickly. You'll build a simple "Welcome Email" process that demonstrates core concepts like step dependencies, error handling, and result passing.

## Prerequisites

- **Rails application** (7.2+) with PostgreSQL
- **Ruby 3.2+**  
- **Basic Rails knowledge** (models, controllers, ActiveJob)

## Installation & Setup (3 minutes)

### 1. Add Tasker to your Gemfile

```ruby
# Gemfile
gem 'tasker', git: 'https://github.com/jcoletaylor/tasker.git'
```

### 2. Install and configure

```bash
bundle install
bundle exec rails generate tasker:install
bundle exec rails db:migrate
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

```ruby
# app/tasks/welcome_user/welcome_handler.rb
module WelcomeUser
  class WelcomeHandler < Tasker::TaskHandler::Base
    TASK_NAME = 'send_welcome_email'
    NAMESPACE = 'welcome_user'
    VERSION = '1.0.0'
    
    register_handler(TASK_NAME, namespace_name: NAMESPACE, version: VERSION)
    
    define_step_templates do |templates|
      templates.define(
        name: 'validate_user',
        handler_class: 'WelcomeUser::StepHandler::ValidateUserHandler'
      )
      
      templates.define(
        name: 'generate_content',
        depends_on_step: 'validate_user',
        handler_class: 'WelcomeUser::StepHandler::GenerateContentHandler'
      )
      
      templates.define(
        name: 'send_email',
        depends_on_step: 'generate_content',
        handler_class: 'WelcomeUser::StepHandler::SendEmailHandler',
        retryable: true,
        retry_limit: 3
      )
    end
    
    def schema
      {
        type: 'object',
        required: ['user_id'],
        properties: {
          user_id: { type: 'integer' }
        }
      }
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
        raise Tasker::PermanentError, "User not found: #{user_id}" unless user
        
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
          # Temporary failure - retry
          raise Tasker::RetryableError, "SMTP server busy: #{e.message}"
        rescue Net::SMTPFatalError => e
          # Permanent failure - don't retry
          raise Tasker::PermanentError, "Invalid email address: #{e.message}"
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
puts "Status: #{task.status}"

# View step details
task.workflow_step_sequences.last.steps.each do |step|
  puts "#{step.name}: #{step.status}"
  puts "  Result: #{step.result}" if step.result
end
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