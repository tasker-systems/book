# Setup Troubleshooting

Having trouble with the examples? This guide covers common issues and their solutions.

## 🚨 Quick Diagnostics

Run this diagnostic script to identify common problems:

```bash
# Save as check-environment.sh
#!/bin/bash

echo "🔍 Tasker Environment Diagnostics"
echo "================================="

# Check Ruby version
echo -n "Ruby version: "
ruby -v 2>/dev/null || echo "❌ Ruby not found"

# Check Rails version
echo -n "Rails version: "
rails -v 2>/dev/null || echo "❌ Rails not found"

# Check PostgreSQL
echo -n "PostgreSQL: "
psql --version 2>/dev/null || echo "❌ PostgreSQL not found"

# Check Redis
echo -n "Redis: "
redis-server --version 2>/dev/null || echo "❌ Redis not found"

# Check Git
echo -n "Git: "
git --version 2>/dev/null || echo "❌ Git not found"

# Check internet connectivity
echo -n "GitHub connectivity: "
curl -s --max-time 5 https://github.com >/dev/null && echo "✅ OK" || echo "❌ Failed"

echo ""
echo "If any items show ❌, install them before proceeding."
```

## 🐛 Common Issues

### Installation Problems

#### "Ruby version not supported"

**Error**: `Ruby 3.0+ is required. Found: 2.x.x`

**Solution**:
```bash
# macOS with Homebrew
brew install ruby

# Ubuntu/Debian
sudo apt-get install ruby-dev

# Using rbenv (recommended)
rbenv install 3.2.0
rbenv global 3.2.0
```

#### "Rails not found"

**Error**: `rails: command not found`

**Solution**:
```bash
gem install rails
# If permission errors:
gem install --user-install rails
# Add to PATH: ~/.gem/ruby/X.X.X/bin
```

#### "PostgreSQL connection failed"

**Error**: `could not connect to server: Connection refused`

**Solution**:
```bash
# macOS with Homebrew
brew services start postgresql

# Ubuntu/Debian
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Docker (alternative)
docker run -d -p 5432:5432 -e POSTGRES_PASSWORD=password postgres:13
```

#### "Redis connection failed"

**Error**: `Error connecting to Redis on localhost:6379`

**Solution**:
```bash
# macOS with Homebrew
brew services start redis

# Ubuntu/Debian
sudo systemctl start redis-server

# Docker (alternative)
docker run -d -p 6379:6379 redis:7
```

### Download Problems

#### "curl failed to download script"

**Error**: `curl: (7) Failed to connect to raw.githubusercontent.com`

**Solution**:
```bash
# Check internet connection
ping google.com

# Try alternative download
wget https://raw.githubusercontent.com/tasker-systems/tasker/main/blog-examples/ecommerce-reliability/setup.sh
chmod +x setup.sh
./setup.sh
```

#### "Permission denied"

**Error**: `Permission denied (publickey)`

**Solution**:
```bash
# Use HTTPS instead of SSH
git clone https://github.com/tasker-systems/tasker.git
# Instead of: git clone git@github.com:tasker-systems/tasker.git
```

### Application Setup Problems

#### "Bundle install failed"

**Error**: `An error occurred while installing pg (1.x.x)`

**Solution**:
```bash
# macOS
brew install postgresql
gem install pg

# Ubuntu/Debian
sudo apt-get install libpq-dev
gem install pg

# If still failing, specify config:
gem install pg -- --with-pg-config=/usr/local/bin/pg_config
```

#### "Database migration failed"

**Error**: `PG::ConnectionBad: could not connect to server`

**Solution**:
```bash
# Check if PostgreSQL is running
pg_isready

# Create database if needed
createdb ecommerce_blog_demo_development

# Or use Rails database tasks
bundle exec rails db:create
bundle exec rails db:migrate
```

#### "Sidekiq won't start"

**Error**: `Redis::CannotConnectError`

**Solution**:
```bash
# Start Redis first
redis-server

# Check Redis is accessible
redis-cli ping  # Should return "PONG"

# Then start Sidekiq
bundle exec sidekiq
```

### Runtime Problems

#### "Task handler not found"

**Error**: `Tasker::ProceduralError: No registered class for order_processing`

**Solution**:
```bash
# Restart Rails server to reload handlers
bundle exec rails server

# Check handlers are registered
bundle exec rails runner "puts Tasker::HandlerFactory.instance.stats"
```

#### "Step failures not retrying"

**Error**: Steps fail immediately instead of retrying

**Solution**:
```bash
# Check Sidekiq is processing jobs
# Visit http://localhost:4567 (Sidekiq web UI)

# Verify retry configuration in step templates
grep -r "retryable.*true" app/tasks/

# Check error types are retryable
# NonRetryableError won't retry, RetryableError will
```

#### "No route matches"

**Error**: `ActionController::RoutingError: No route matches [POST] "/checkout"`

**Solution**:
```bash
# Check routes are mounted
bundle exec rails routes | grep tasker
bundle exec rails routes | grep checkout

# Verify engine is mounted in config/routes.rb
grep "mount.*Tasker" config/routes.rb
```

### Testing Problems

#### "Curl commands fail"

**Error**: `curl: (7) Failed to connect to localhost port 3000`

**Solution**:
```bash
# Check Rails server is running
ps aux | grep rails

# Start server if not running
bundle exec rails server

# Check correct port
lsof -i :3000
```

#### "Payment simulator returns errors"

**Error**: All payments fail with "simulator not found"

**Solution**:
```bash
# Check PaymentSimulator is loaded
bundle exec rails runner "puts PaymentSimulator.charge(amount: 10, payment_method: 'test')"

# Restart server to reload simulators
bundle exec rails server
```

## 🔧 Environment-Specific Issues

### macOS

#### "Command not found after installation"

**Solution**:
```bash
# Update PATH in ~/.zshrc or ~/.bash_profile
echo 'export PATH="/usr/local/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
```

#### "Homebrew permissions"

**Solution**:
```bash
# Fix Homebrew permissions
sudo chown -R $(whoami) /usr/local/Homebrew
```

### Linux (Ubuntu/Debian)

#### "Permission denied for gem install"

**Solution**:
```bash
# Install gems locally instead of system-wide
echo 'export GEM_HOME="$HOME/.gem"' >> ~/.bashrc
echo 'export PATH="$GEM_HOME/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### "Build tools missing"

**Solution**:
```bash
sudo apt-get update
sudo apt-get install build-essential libssl-dev libreadline-dev zlib1g-dev
```

### Windows (WSL)

#### "WSL networking issues"

**Solution**:
```bash
# In WSL, access via localhost
curl http://localhost:3000/checkout

# If not working, try WSL IP
ip addr show eth0
# Use the inet address in curl commands
```

## 📞 Getting Additional Help

### Before Asking for Help

1. **Run the diagnostic script** above
2. **Check the error logs**: `tail -f log/development.log`
3. **Try a clean environment**: Fresh terminal, restart services
4. **Search existing issues**: Someone might have solved it already

### Where to Get Help

1. **GitHub Issues**: [Create a new issue](https://github.com/tasker-systems/tasker/issues)
   - Include diagnostic output
   - Share error messages
   - Describe what you were trying to do

2. **GitHub Discussions**: [Ask the community](https://github.com/tasker-systems/tasker/discussions)
   - General questions about workflows
   - Best practices
   - Use case discussions

3. **Documentation**: Check the [official Tasker docs](https://github.com/tasker-systems/tasker/docs/)

### Creating Good Bug Reports

Include this information:

```markdown
**Environment**:
- OS: [macOS 13.0, Ubuntu 22.04, etc.]
- Ruby version: [3.2.0]
- Rails version: [7.0.4]
- Tasker version: [2.5.0]

**What I was trying to do**:
[Describe the goal]

**What I expected**:
[Expected behavior]

**What actually happened**:
[Actual behavior with error messages]

**Steps to reproduce**:
1. Run command X
2. See error Y
3. ...

**Diagnostic output**:
[Paste the output from check-environment.sh]
```

## 🚀 Performance Troubleshooting

### Slow Workflow Execution

**Symptoms**: Tasks take much longer than expected

**Diagnosis**:
```bash
# Check database performance
bundle exec rails runner "
  require 'benchmark'
  puts Benchmark.measure { Tasker::Task.limit(10).to_a }
"

# Check Redis performance
redis-cli --latency-history -h localhost -p 6379
```

**Solutions**:
- Add database indexes for large task volumes
- Tune Redis memory settings
- Use connection pooling for external APIs

### Memory Issues

**Symptoms**: Application consuming too much memory

**Diagnosis**:
```bash
# Monitor memory usage
ps aux | grep ruby
top -p $(pgrep ruby)
```

**Solutions**:
- Reduce Sidekiq concurrency
- Implement result cleanup for old tasks
- Use streaming for large data processing

---

*Most issues have simple solutions. When in doubt, start fresh with a clean environment and follow the diagnostic steps.*
