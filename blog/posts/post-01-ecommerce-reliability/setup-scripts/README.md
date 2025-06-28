# Setup Scripts

This directory contains setup scripts and tools for quickly trying the blog examples.

## 🚀 Quick Start

### Blog Setup Script
The primary way to try any chapter example:

```bash
# Try Chapter 1: E-commerce Reliability
curl -fsSL https://raw.githubusercontent.com/jcoletaylor/tasker/main/blog-examples/ecommerce-reliability/setup.sh | bash
```

This script:
1. **Leverages existing infrastructure**: Uses Tasker's proven `curl | sh` installer pattern
2. **Creates complete applications**: Full Rails app with working examples
3. **Provides chapter-specific context**: Tailored instructions and test scenarios
4. **Maintains consistency**: Same quality and patterns as main Tasker tooling

### Manual Setup
If you prefer to explore first:

```bash
# Download and examine the script
curl -fsSL https://raw.githubusercontent.com/jcoletaylor/tasker/main/blog-examples/ecommerce-reliability/setup.sh > setup.sh

# Review the script
cat setup.sh

# Run when ready
chmod +x setup.sh
./setup.sh
```

## 🛠️ How It Works

### Integration with Existing Tooling

Instead of creating separate blog-specific installers, we use a thin wrapper around Tasker's established application generator:

```bash
# Our script calls the main installer with specific parameters
curl -fsSL "$INSTALL_SCRIPT_URL" | bash -s -- \
    --app-name "ecommerce-blog-demo" \
    --tasks ecommerce \
    --non-interactive
```

### Benefits of This Approach

| Aspect | Custom Setup | Integrated Pattern |
|--------|--------------|-------------------|
| **Setup Time** | 10+ minutes | 2-3 minutes |
| **Commands Required** | 8-10 commands | 1 command |
| **Maintenance** | High (duplicate logic) | Low (reuses existing) |
| **Consistency** | Custom patterns | Standard Tasker patterns |
| **Error Handling** | Need to reimplement | Inherits proven reliability |

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

After running any setup script:

```bash
# Start the services
cd [app-name]
redis-server &
bundle exec sidekiq &
bundle exec rails server

# Test the workflow
curl -X POST http://localhost:3000/checkout \
  -H "Content-Type: application/json" \
  -d '{"checkout": {...}}'

# Monitor workflow execution  
curl http://localhost:3000/order_status/TASK_ID
```

Each chapter includes comprehensive testing guides with multiple scenarios.

## 🔧 Troubleshooting

### Common Issues

**"Setup script fails to download"**
- Check internet connectivity
- Try downloading manually: `curl -O [script-url]`
- Use `wget` as alternative: `wget [script-url]`

**"Rails app creation fails"**
- Ensure Ruby 3.0+ and Rails 7.0+ are installed
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

The same pattern scales for all upcoming chapters:

```bash
# Chapter 2: Data Pipeline Resilience (Coming Q1 2024)
curl -fsSL .../blog-examples/data-pipeline-resilience/setup.sh | bash

# Chapter 3: Microservices Coordination (Coming Q2 2024)  
curl -fsSL .../blog-examples/microservices-coordination/setup.sh | bash
```

Each will be a simple wrapper around the main installer with chapter-specific:
- Template selection (`--tasks parameter`)
- Contextual documentation
- Testing scenarios
- Sample data

## 📚 Related Documentation

- **[Tasker Application Generator](https://github.com/jcoletaylor/tasker/blob/main/docs/APPLICATION_GENERATOR.md)**: Complete documentation of the underlying generator
- **[Installation Guide](https://github.com/jcoletaylor/tasker/blob/main/README.md#installation)**: Manual Tasker setup instructions
- **[Troubleshooting Guide](../appendices/troubleshooting.md)**: Comprehensive problem-solving guide

---

*These setup scripts provide the fastest path from curiosity to working example, while maintaining the quality and consistency of the main Tasker tooling.*
