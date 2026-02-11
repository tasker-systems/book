# Microservices Coordination Blog Post

This directory contains the blog post about orchestrating microservices dependencies without the chaos using Tasker's sophisticated coordination capabilities.

## 📝 Blog Post

- **[blog-post.md](./blog-post.md)** - The main blog post content

## 🧪 **Tested Code Examples**

All code examples for this blog post are now **tested and validated** in the main Tasker repository:

- **[Complete Working Examples](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_03_microservices_coordination)** - All step handlers, configurations, and tests
- **[YAML Configuration](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_03_microservices_coordination/config/user_registration_handler.yaml)** - Complete task configuration with service coordination
- **[Step Handlers](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_03_microservices_coordination/step_handlers)** - All Ruby step handler implementations including circuit breaker patterns
- **[Circuit Breaker Documentation](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_03_microservices_coordination/step_handlers/CIRCUIT_BREAKER_EXPLANATION.md)** - Detailed explanation of Tasker's SQL-driven circuit breaker architecture
- **[RSpec Tests](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_03_microservices_coordination)** - Complete test suite proving all examples work

## 🏃‍♂️ **Quick Start**

```bash
# Clone the repository
git clone https://github.com/tasker-systems/tasker.git
cd tasker/spec/blog/post_03_microservices_coordination

# Run the setup
./setup-scripts/setup.sh

# Run the microservices demo
./demo/user_registration_demo.rb
```

## 📊 **What's Tested**

- ✅ Service orchestration across multiple APIs
- ✅ Correlation ID tracking for distributed debugging
- ✅ Circuit breaker patterns with typed error handling
- ✅ Idempotent operations across service boundaries
- ✅ Graceful degradation when services are unavailable
- ✅ SQL-driven coordination state management

## 🔗 **Related Files**

- **[TESTING.md](./TESTING.md)** - Testing approach and scenarios
- **[setup-scripts/](./setup-scripts/)** - Setup and demo scripts
- **[preview.md](./preview.md)** - Blog post preview

## 🎯 **Key Takeaways**

The examples demonstrate:
1. **Service orchestration patterns** with API step handlers
2. **SQL-driven circuit breaker architecture** (superior to in-memory patterns)
3. **Typed error handling** for intelligent retry logic
4. **Correlation ID tracking** for distributed debugging
5. **Idempotent operations** across service boundaries
6. **Graceful degradation** strategies

All code is production-ready and thoroughly tested in the Tasker engine.
