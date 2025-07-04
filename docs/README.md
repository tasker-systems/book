# Tasker Developer Documentation Hub

[![GitHub Repository](https://img.shields.io/badge/GitHub-tasker--systems%2Ftasker-blue?logo=github)](https://github.com/tasker-systems/tasker)
[![Ruby](https://img.shields.io/badge/Ruby-3.2%2B-red.svg)](https://github.com/tasker-systems/tasker)
[![Rails](https://img.shields.io/badge/Rails-7.2%2B-red.svg)](https://github.com/tasker-systems/tasker)
[![MIT License](https://img.shields.io/badge/License-MIT-green.svg)](https://github.com/tasker-systems/tasker/blob/main/LICENSE)

> **Complete reference for building production workflows with the [Tasker Rails Engine](https://github.com/tasker-systems/tasker)**

This documentation hub provides everything you need to master **[Tasker](https://github.com/tasker-systems/tasker)**, from your first workflow to enterprise-scale implementations. Use this alongside the [engineering stories](../blog/) to see patterns in action.

## 🎯 Quick Navigation

**Just getting started?** → [Quick Start Guide](QUICK_START.md)
**Building your first workflow?** → [Developer Guide](DEVELOPER_GUIDE.md)
**Ready for production?** → [Production Operations](#production-operations)
**Debugging issues?** → [Troubleshooting](TROUBLESHOOTING.md)

---

## 📚 Documentation Sections

### Getting Started
- **[System Overview](OVERVIEW.md)** - Complete system architecture and capabilities
- **[Quick Start Guide](QUICK_START.md)** - Build your first workflow in 15 minutes
- **[Core Concepts](core-concepts.md)** - Understanding Tasker's architecture

### Developer Reference
- **[Developer Guide](DEVELOPER_GUIDE.md)** - Comprehensive implementation guide (80KB, 2542 lines)
- **[REST API Reference](REST_API.md)** - Complete HTTP API documentation
- **[SQL Functions Reference](SQL_FUNCTIONS.md)** - Extensive SQL functions reference (39KB)
- **[Analytics System](ANALYTICS.md)** - Performance analytics and bottleneck analysis (v1.0.0+)
- **[Application Generator](APPLICATION_GENERATOR.md)** - Application generation guide
- **[Workflow Patterns](workflow-patterns.md)** - Common workflow designs
- **[Circuit Breaker Architecture](CIRCUIT_BREAKER.md)** - SQL-driven resilience patterns

### Configuration & Setup
- **[🚀 YAML Configuration](EXECUTION_CONFIGURATION.md)** - Declarative workflow definition
- **[Authentication & Authorization](AUTH.md)** - Comprehensive security guide (49KB)
- **[Event System](EVENT_SYSTEM.md)** - Observability and integrations
- **[Registry Systems](REGISTRY_SYSTEMS.md)** - Handler organization and discovery

### Production Operations
- **[Health Monitoring](HEALTH.md)** - Production health endpoints
- **[Metrics & Performance](METRICS.md)** - Performance monitoring and optimization
- **[Telemetry & Observability](TELEMETRY.md)** - OpenTelemetry and comprehensive monitoring (29KB)
- **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions

### Advanced Topics
- **[System Flow Charts](FLOW_CHART.md)** - Visual workflow representation

- **[Task Execution Control Flow](TASK_EXECUTION_CONTROL_FLOW.md)** - Deep dive into orchestration patterns
- **[Project Roadmap](ROADMAP.md)** - Future development plans

### Strategic Documentation
- **[Vision & Roadmap](VISION.md)** - Strategic roadmap for distributed AI-integrated workflow orchestration

---

## 🚀 Real-World Examples

Learn from detailed engineering stories that show **[Tasker](https://github.com/tasker-systems/tasker)** solving real problems:

### [Chapter 1: E-commerce Checkout Reliability](../blog/posts/post-01-ecommerce-reliability/)
**Problem:** Black Friday checkout meltdowns
**Solution:** Reliable workflow with automatic retry and dependency management
**Patterns:** Linear workflow, error handling, monitoring integration

### [Chapter 2: Data Pipeline Resilience](../blog/posts/post-02-data-pipeline-resilience/)
**Problem:** 3 AM ETL failures requiring manual intervention
**Solution:** Parallel data processing with intelligent retry and progress tracking
**Patterns:** Diamond pattern, parallel execution, progress monitoring

### [Chapter 3: Microservices Coordination](../blog/posts/post-03-microservices-coordination/)
**Problem:** Service coordination nightmare after microservices migration
**Solution:** Leverage Tasker's SQL-driven circuit breaker architecture for resilient service orchestration
**Patterns:** API orchestration, distributed circuit breakers, typed error handling

### More Engineering Stories (Coming Soon)
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
- [System Overview](OVERVIEW.md) - Complete system architecture
- [Quick Start Guide](QUICK_START.md) - Build your first workflow
- [Core Concepts](core-concepts.md) - Understand the architecture
- [Simple Examples](../blog/posts/post-01-ecommerce-reliability/) - See basic patterns

### 2. **Development Skills**
- [Developer Guide](DEVELOPER_GUIDE.md) - Comprehensive implementation (80KB guide)
- [YAML Configuration](EXECUTION_CONFIGURATION.md) - Declarative workflows
- [Application Generator](APPLICATION_GENERATOR.md) - Rapid development tools

### 3. **Advanced Patterns**
- [Workflow Patterns](workflow-patterns.md) - Diamond, parallel, conditional
- [Event System](EVENT_SYSTEM.md) - Monitoring and integrations
- [Complex Examples](../blog/posts/post-02-data-pipeline-resilience/) - Data pipelines

### 4. **Production Deployment**
- [Authentication & Authorization](AUTH.md) - Comprehensive security (49KB guide)
- [REST API](REST_API.md) - HTTP API integration
- [Health Monitoring](HEALTH.md) - Production readiness
- [Metrics & Performance](METRICS.md) - Scale and optimize

### 5. **Enterprise Features**
- [Registry Systems](REGISTRY_SYSTEMS.md) - Multi-team organization
- [Telemetry & Observability](TELEMETRY.md) - Complete observability (29KB guide)
- [SQL Functions](SQL_FUNCTIONS.md) - High-performance operations (39KB reference)

---

## 🔗 Tasker Resources

### Official Repository & Documentation
- **[📦 Main Repository](https://github.com/tasker-systems/tasker)** - Source code, issues, and releases
- **[📖 Ruby API Documentation](https://rubydoc.info/github/tasker-systems/tasker)** - Complete API reference
- **[📋 OpenAPI Specification](https://github.com/tasker-systems/tasker/blob/main/docs/openapi.yml)** - REST API specification
- **[🚀 Installation Scripts](https://github.com/tasker-systems/tasker/tree/main/scripts)** - Quick setup tools

### Community & Support
- **[👥 GitHub Discussions](https://github.com/tasker-systems/tasker/discussions)** - Questions and patterns
- **[🐛 Issue Tracker](https://github.com/tasker-systems/tasker/issues)** - Bug reports and feature requests
- **[📚 Stack Overflow](https://stackoverflow.com/questions/tagged/tasker-ruby)** - Tag: `tasker-ruby`

### Related Tools & Integrations
- **[Sidekiq](https://sidekiq.org/)** - Recommended background processor
- **[PostgreSQL](https://postgresql.org/)** - Required database (SQL functions)
- **[OpenTelemetry](https://opentelemetry.io/)** - Distributed tracing integration
- **[Prometheus](https://prometheus.io/)** - Metrics collection

---

*This documentation hub integrates content from the official **[Tasker Rails Engine](https://github.com/tasker-systems/tasker)** with practical examples from real engineering challenges. Start with the [System Overview](OVERVIEW.md) or [Quick Start Guide](QUICK_START.md) and work your way through the learning path.*
