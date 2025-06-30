# Setup Scripts

This directory contains setup scripts and tools for quickly trying the blog examples.

## 🚀 Quick Start

### Option 1: Docker Setup (Recommended) 🐳
The fastest way to try the example with zero local dependencies:

```bash
# Docker with observability stack (Jaeger + Prometheus)
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name ecommerce-reliability-demo \
  --tasks ecommerce \
  --docker \
  --with-observability \
  --non-interactive

cd ecommerce-reliability-demo
./bin/docker-dev up-full
```

**Includes:**
- Rails app with live code reloading
- PostgreSQL 15 database
- Redis 7 for background jobs
- Jaeger tracing UI (http://localhost:16686)
- Prometheus metrics (http://localhost:9090)

### Option 2: Traditional Setup
For users who prefer local development:

```bash
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name ecommerce-reliability-demo \
  --tasks ecommerce \
  --non-interactive
```

**Requirements:** Ruby 3.2+, Rails 7.2+, PostgreSQL, Redis

### Interactive Setup
Use our interactive setup script for more control:

```bash
# Download our Chapter 1 setup script
curl -fsSL https://raw.githubusercontent.com/your-gitbook-repo/main/blog/posts/post-01-ecommerce-reliability/setup-scripts/setup.sh | bash

# This script offers:
# 1. Traditional Rails setup
# 2. Docker-based setup
# 3. Docker with full observability stack
```

## 🛠️ How It Works

### Integration with Tasker v2.6.0 Application Generator

We leverage Tasker's production-ready application generator with new Docker support:

```bash
# Traditional setup
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
    --app-name ecommerce-reliability-demo \
    --tasks ecommerce \
    --non-interactive

# Docker setup with observability
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
    --app-name ecommerce-reliability-demo \
    --tasks ecommerce \
    --docker \
    --with-observability \
    --non-interactive
```

### Benefits of Docker vs Traditional Setup

| Aspect | Traditional Setup | Docker Setup | Docker + Observability |
|--------|------------------|--------------|----------------------|
| **Local Dependencies** | Ruby, Rails, PostgreSQL, Redis | Docker only | Docker only |
| **Setup Time** | 5-10 minutes | 2-3 minutes | 3-4 minutes |
| **Commands to Start** | 3-4 terminals | 1 command | 1 command |
| **Observability** | Manual setup | Not included | Built-in (Jaeger, Prometheus) |
| **Cleanup** | Manual | `./bin/docker-dev clean` | `./bin/docker-dev clean` |
| **Cross-Platform** | Varies by OS | Identical everywhere | Identical everywhere |

## 📋 What Gets Created

Each setup script creates a complete Rails application with:

### **Core Infrastructure**
- **Rails application** with PostgreSQL database
- **All Tasker migrations** and database objects
- **Redis and Sidekiq** for background job processing
- **Complete routes** and API endpoints

### **Chapter-Specific Content**
- **Task handlers** implementing the chapter's workflow
- **Step handlers** for each workflow step
- **Models and controllers** for the domain (e-commerce, data pipeline, etc.)
- **Test scenarios** demonstrating reliability features
- **Sample data** for immediate testing

### **Development Tools**
- **Comprehensive documentation** for the specific example
- **Testing scripts** for various failure scenarios
- **Monitoring setup** (when observability features are included)

## 🧪 Testing the Setup

### Docker Environment
```bash
cd ecommerce-reliability-demo

# Start all services (includes observability)
./bin/docker-dev up-full

# Test the workflow
curl -X POST http://localhost:3000/checkout \
  -H "Content-Type: application/json" \
  -d '{"checkout": {...}}'

# Monitor with built-in tools
# Jaeger UI: http://localhost:16686 (trace workflows)
# Prometheus: http://localhost:9090 (metrics)
# GraphQL: http://localhost:3000/tasker/graphql

# Stop all services
./bin/docker-dev down
```

### Traditional Environment
```bash
cd ecommerce-reliability-demo

# Start services in separate terminals
redis-server
bundle exec sidekiq
bundle exec rails server

# Test the same endpoints
curl -X POST http://localhost:3000/checkout ...
```

Each chapter includes comprehensive testing guides with multiple failure scenarios.

## 🔧 Troubleshooting

### Docker Issues

**"Docker setup fails"**
- Ensure Docker is installed and running: `docker --version`
- Check Docker daemon: `docker ps`
- Free up disk space: `docker system prune`

**"Services won't start"**
- Check port conflicts: `./bin/docker-dev status`
- View service logs: `./bin/docker-dev logs`
- Restart services: `./bin/docker-dev restart`

**"Can't access observability UIs"**
- Verify full stack is running: `./bin/docker-dev up-full`
- Check if ports are available: `lsof -i :16686,9090`
- Wait for services to initialize (30-60 seconds)

### Traditional Setup Issues

**"Rails app creation fails"**
- Ensure Ruby 3.2+ and Rails 7.2+ are installed
- Check PostgreSQL is running
- Verify all dependencies in diagnostic output

**"Background jobs not processing"**
- Start Redis: `redis-server`
- Start Sidekiq: `bundle exec sidekiq`
- Check Redis connectivity: `redis-cli ping`

### Getting Help

1. **Run diagnostics** from the troubleshooting guide
2. **Check logs**: `tail -f log/development.log`
3. **Try clean environment**: Fresh terminal, restart services
4. **Report issues**: Include diagnostic output and error messages

## 🔮 Future Chapters

All upcoming chapters will support both traditional and Docker-based setup:

```bash
# Chapter 2: Data Pipeline Resilience (Coming Soon)
# Docker with observability
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name data-pipeline-demo \
  --tasks data_processing \
  --docker \
  --with-observability

# Chapter 3: Microservices Coordination (Planned)
# Docker setup
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name microservices-demo \
  --tasks inventory,notifications,integrations \
  --docker
```

**Each chapter provides:**
- **Docker-first approach** with zero local dependencies
- **Built-in observability** (Jaeger + Prometheus)
- **Chapter-specific task templates**
- **Comprehensive testing scenarios**
- **Production-ready examples**

## 📚 Related Documentation

- **[Tasker Application Generator](../../../../docs/APPLICATION_GENERATOR.md)**: Complete documentation of the underlying generator
- **[Getting Started Guide](../../../../getting-started.md)**: Manual Tasker setup instructions
- **[Troubleshooting Guide](../../../../appendices/troubleshooting.md)**: Comprehensive problem-solving guide

---

*These setup scripts provide the fastest path from curiosity to working example, while maintaining the quality and consistency of the main Tasker tooling.*
