# Tasker Developer Documentation Hub

> **Complete reference for building production workflows with Tasker**

This documentation hub provides everything you need to master Tasker, from your first workflow to enterprise-scale implementations. Use this alongside the [engineering stories](../blog/) to see patterns in action.

## 🎯 Quick Navigation

**Just getting started?** → [Quick Start Guide](quick-start.md)  
**Building your first workflow?** → [Developer Guide](developer-guide.md)  
**Ready for production?** → [Production Features](production-features.md)  
**Debugging issues?** → [Troubleshooting](troubleshooting.md)

---

## 📚 Documentation Sections

### Getting Started
- **[Quick Start Guide](quick-start.md)** - Build your first workflow in 15 minutes
- **[Installation & Setup](installation.md)** - Complete setup instructions  
- **[Core Concepts](core-concepts.md)** - Understanding Tasker's architecture

### Developer Reference
- **[Developer Guide](developer-guide.md)** - Comprehensive implementation guide
- **[API Reference](api-reference.md)** - Complete class and method documentation
- **[YAML Configuration](yaml-configuration.md)** - Declarative workflow definition
- **[Testing Guide](testing-guide.md)** - Testing workflows and step handlers

### Production Features
- **[Authentication & Authorization](authentication.md)** - Secure your workflows
- **[REST API](rest-api.md)** - Complete HTTP API documentation  
- **[Health Monitoring](health-monitoring.md)** - Production health endpoints
- **[Telemetry & Observability](telemetry.md)** - OpenTelemetry and metrics
- **[Performance](performance.md)** - High-performance SQL functions

### Advanced Topics
- **[Event System](event-system.md)** - Observability and integrations
- **[Registry Systems](registry-systems.md)** - Handler organization and discovery
- **[Workflow Patterns](workflow-patterns.md)** - Common workflow designs
- **[Namespace & Versioning](namespace-versioning.md)** - Enterprise organization

### Troubleshooting & Maintenance
- **[Troubleshooting](troubleshooting.md)** - Common issues and solutions
- **[Debugging Guide](debugging.md)** - Debug workflows and step handlers
- **[Migration Guide](migration-guide.md)** - Upgrading between versions
- **[Best Practices](best-practices.md)** - Production deployment guidelines

---

## 🚀 Real-World Examples

Learn from detailed engineering stories that show Tasker solving real problems:

### [Chapter 1: E-commerce Checkout Reliability](../blog/posts/post-01-ecommerce-reliability/)
**Problem:** Black Friday checkout meltdowns  
**Solution:** Reliable workflow with automatic retry and dependency management  
**Patterns:** Linear workflow, error handling, monitoring integration

### [Chapter 2: Data Pipeline Resilience](../blog/posts/post-02-data-pipeline-resilience/)  
**Problem:** 3 AM ETL failures requiring manual intervention  
**Solution:** Parallel data processing with intelligent retry and progress tracking  
**Patterns:** Diamond pattern, parallel execution, progress monitoring

### More Engineering Stories (Coming Soon)
- **Chapter 3:** Microservices Coordination - Orchestrating 6 API calls for user registration
- **Chapter 4:** Team Scaling - Managing workflows across 8 engineering teams  
- **Chapter 5:** Production Observability - From black box to complete visibility
- **Chapter 6:** Enterprise Security - SOC 2 compliance for workflow engines

---

## 🛠️ Developer Tools

### Rails Generators
```bash
# Generate complete workflow
rails generate tasker:workflow ecommerce process_order

# Generate step handler
rails generate tasker:step_handler ecommerce process_order validate_payment
```

### Testing Infrastructure
```ruby
# Built-in test helpers
include Tasker::SpecHelpers

result = run_task_workflow(
  'process_order',
  namespace: 'ecommerce',
  context: { order_id: 123 }
)

expect(result.status).to eq('completed')
```

### Debug Tools
```ruby
# Task inspection
task = Tasker::Task.find(task_id)
puts task.inspect_execution

# Performance analysis  
Tasker::Analytics.workflow_performance('ecommerce', 'process_order')
```

---

## 🎯 Learning Path

### 1. **Foundation (Start Here)**
- [Quick Start Guide](quick-start.md) - Build your first workflow
- [Core Concepts](core-concepts.md) - Understand the architecture
- [Simple Examples](../blog/posts/post-01-ecommerce-reliability/) - See basic patterns

### 2. **Development Skills** 
- [Developer Guide](developer-guide.md) - Comprehensive implementation  
- [YAML Configuration](yaml-configuration.md) - Declarative workflows
- [Testing Guide](testing-guide.md) - Test your workflows

### 3. **Advanced Patterns**
- [Workflow Patterns](workflow-patterns.md) - Diamond, parallel, conditional
- [Event System](event-system.md) - Monitoring and integrations
- [Complex Examples](../blog/posts/post-02-data-pipeline-resilience/) - Data pipelines

### 4. **Production Deployment**
- [Authentication](authentication.md) - Secure your workflows
- [REST API](rest-api.md) - HTTP API integration
- [Health Monitoring](health-monitoring.md) - Production readiness
- [Performance](performance.md) - Scale and optimize

### 5. **Enterprise Features**
- [Namespace & Versioning](namespace-versioning.md) - Multi-team organization
- [Telemetry](telemetry.md) - Observability and tracing
- [Best Practices](best-practices.md) - Production guidelines

---

## 🔗 External Resources

### Official Documentation  
- **[GitHub Repository](https://github.com/jcoletaylor/tasker)** - Source code and issues
- **[Ruby API Docs](https://rubydoc.info/github/jcoletaylor/tasker)** - Complete API reference
- **[OpenAPI Spec](https://github.com/jcoletaylor/tasker/blob/main/docs/openapi.yml)** - REST API specification

### Community
- **[GitHub Discussions](https://github.com/jcoletaylor/tasker/discussions)** - Questions and patterns
- **[Stack Overflow](https://stackoverflow.com/questions/tagged/tasker-ruby)** - Tag: `tasker-ruby`

### Related Tools
- **[Sidekiq](https://sidekiq.org/)** - Recommended background processor
- **[PostgreSQL](https://postgresql.org/)** - Required database
- **[OpenTelemetry](https://opentelemetry.io/)** - Distributed tracing
- **[Prometheus](https://prometheus.io/)** - Metrics collection

---

*This documentation hub integrates content from the official Tasker engine with practical examples from real engineering challenges. Start with the Quick Start Guide and work your way through the learning path.*