# Chapter 3: Setup Scripts

> ⚠️ **Note**: Docker-based setup scripts are coming soon! The current implementation focuses on the core Tasker workflow patterns.

## 🚀 Quick Setup (Coming Soon)

The full demo will include:
- 4 mock microservices (User, Billing, Preferences, Notification)
- Docker Compose configuration for easy local development
- Pre-configured service endpoints with various failure scenarios
- Monitoring dashboard to observe circuit breaker behavior

## 📋 What Will Be Included

### Mock Services
1. **User Service** (Port 3001)
   - User creation and management
   - Configurable failure rates for testing

2. **Billing Service** (Port 3002)
   - Billing profile creation
   - Rate limiting simulation

3. **Preferences Service** (Port 3003)
   - User preferences management
   - Intermittent availability for testing graceful degradation

4. **Notification Service** (Port 3004)
   - Welcome email sending
   - Rate limit responses for testing backoff

### Setup Features
- One-command setup: `bash setup.sh`
- Docker Compose for all services
- Pre-loaded test data
- Failure scenario configurations

## 🔧 Manual Setup (Current)

Until the Docker setup is ready, you can explore the code patterns:

```bash
# 1. Copy the code examples to your Tasker application
cp -r ../code-examples/* your-tasker-app/

# 2. Update service URLs in handlers
# Edit each handler's service_url method to point to your services

# 3. Run the workflow
bundle exec rails console
task = UserManagement::UserRegistrationHandler.create(
  email: 'test@example.com',
  name: 'Test User'
)
```

## 📅 Timeline

Docker-based setup scripts are in development and will be available soon. They will provide a complete, runnable demonstration of microservices coordination with Tasker.

## 💡 Key Concepts to Explore

While waiting for the full setup:
1. Review the code examples to understand the patterns
2. Study how `RetryableError` vs `PermanentError` creates circuit breaker behavior
3. Examine the YAML configuration for dependency management
4. Read the [Circuit Breaker Architecture explanation](../code-examples/step_handlers/CIRCUIT_BREAKER_EXPLANATION.md)

## 🤝 Contributing

If you'd like to help create the Docker setup, please check our [contributing guide](../../../../appendices/contributing.md)!