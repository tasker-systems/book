# Quick Start: Get Tasker Running in 5 Minutes

## 🚀 One-Line Installation

### Docker Setup (Recommended)
```bash
# Complete Docker environment with observability
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-demo \
  --tasks ecommerce,inventory,customer \
  --docker \
  --with-observability \
  --non-interactive

cd my-tasker-demo
./bin/docker-dev up-full

# Application: http://localhost:3000
# Jaeger UI: http://localhost:16686
# Prometheus: http://localhost:9090
```

### Traditional Setup
```bash
# Local Ruby/Rails development
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name my-tasker-demo \
  --tasks ecommerce,inventory,customer \
  --non-interactive

cd my-tasker-demo
redis-server &
bundle exec sidekiq &
bundle exec rails server
```

## 🧪 Test Your First Workflow

```bash
# Test a reliable checkout workflow
curl -X POST http://localhost:3000/checkout \
  -H "Content-Type: application/json" \
  -d '{"checkout": {"cart_items": [{"product_id": 1, "quantity": 2}], "payment_info": {"token": "test_success_visa", "amount": 100.00}, "customer_info": {"email": "test@example.com", "name": "Test Customer"}}}'
```

## 📋 Prerequisites

### System Requirements
- **Ruby 3.2+** and **Rails 7.2+**
- **PostgreSQL** (required for Tasker's SQL functions)
- **Redis** (for background job processing)
- **Git** (for downloading examples)

### Quick Environment Check
```bash
# Verify your environment
ruby -v    # Should show 3.2+
rails -v   # Should show 7.2+
psql --version
redis-server --version

# For Docker setup, only need:
docker --version
```

## 🔧 Manual Installation (Existing Rails App)

```ruby
# In your Gemfile
gem 'tasker-engine', '~> 1.0.0'

# Then run
bundle install
bundle exec rails tasker:install:migrations
bundle exec rails tasker:install:database_objects
bundle exec rails db:migrate
```

## 🎮 Explore Your Demo Workflows

Your application includes three complete, production-ready workflows:

### 1. **E-commerce Order Processing**
- **Steps**: Validate order → Process payment → Update inventory → Send confirmation
- **Features**: Retry logic, error handling, real API integration

### 2. **Inventory Management**
- **Steps**: Check stock levels → Update quantities → Generate reports → Send alerts
- **Features**: Conditional logic, parallel processing, data aggregation

### 3. **Customer Management**
- **Steps**: Validate customer → Update profile → Sync external systems → Send notifications
- **Features**: External API calls, data transformation, notification patterns

## 📊 Monitor Your Workflows

```bash
# Access built-in interfaces
open http://localhost:3000/tasker/graphql     # GraphQL API
open http://localhost:3000/tasker/api-docs    # REST API docs
open http://localhost:3000/tasker/metrics     # Prometheus metrics
```

## 🛠️ Create Your First Custom Workflow

```bash
# Generate new workflow structure
rails generate tasker:task_handler WelcomeHandler --module_namespace WelcomeUser

# This creates:
# - app/tasks/welcome_user/welcome_handler.rb (task handler class)
# - config/tasker/tasks/welcome_user/welcome_handler.yaml (workflow configuration)
# - spec/tasks/welcome_user/welcome_handler_spec.rb (test file)
```

## 🆘 Need Help?

- **Full Documentation**: [Complete reference guide](./docs/QUICK_START.md)
- **GitHub Issues**: [Report problems or ask questions](https://github.com/tasker-systems/tasker/issues)
- **Examples**: Browse working code in the generated demo applications

## 🔗 What's Next?

Once you have Tasker running, explore the **[Complete Guide](./getting-started.md)** to understand:
- Why workflow orchestration matters
- How Tasker solves reliability problems
- Real-world engineering scenarios
- Advanced features and patterns

---

*Ready to transform your brittle processes into bulletproof workflows? Start with the examples above and see the difference reliable orchestration makes.*
