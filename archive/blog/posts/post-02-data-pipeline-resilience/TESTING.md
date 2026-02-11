# Chapter 2: Data Pipeline Resilience - Testing Guide

This guide provides comprehensive testing scenarios for the data pipeline resilience patterns demonstrated in this chapter.

## Prerequisites

Ensure you've completed the setup:
```bash
./setup-scripts/blog-setup.sh
cd demo-app
bundle exec sidekiq &
bundle exec rails server
```

## Test Scenarios

### 1. Normal Operation Test

**Objective**: Verify the pipeline runs successfully end-to-end

**Steps**:
```bash
# Run the complete pipeline
./test_pipeline.rb
```

**Expected Results**:
- All 8 steps complete successfully
- Parallel extraction steps (orders, users, products) run simultaneously
- Dependent transformations wait for extractions
- Final insights include customer and product analytics
- Notifications sent to configured channels

### 2. API Testing

**Objective**: Test the REST API endpoints

```bash
# Start pipeline via API
curl -X POST http://localhost:3000/analytics/start \
  -H "Content-Type: application/json" \
  -d '{
    "start_date": "2024-01-01",
    "end_date": "2024-01-07",
    "force_refresh": true
  }'

# Response: {"status":"started","task_id":"uuid","monitor_url":"/analytics/status/uuid"}

# Monitor progress (replace with actual task_id)
curl http://localhost:3000/analytics/status/TASK_ID

# Get final results
curl http://localhost:3000/analytics/results/TASK_ID
```

### 3. Parallel Processing Verification

**Objective**: Confirm independent steps run concurrently

```ruby
# In Rails console - monitor step start times
task_id = "YOUR_TASK_ID"
task = Tasker::Task.find(task_id)
sequence = task.workflow_step_sequences.last

# Check extraction steps started around the same time
extraction_steps = sequence.steps.select { |s| s.name.start_with?('extract_') }
start_times = extraction_steps.map(&:started_at).compact

puts "Extraction step start times:"
extraction_steps.each do |step|
  puts "#{step.name}: #{step.started_at}"
end

# Should see all extraction steps start within seconds of each other
```

### 4. Progress Tracking Test

**Objective**: Verify real-time progress updates work

```ruby
# Start a pipeline and monitor progress
task_request = Tasker::Types::TaskRequest.new(
  name: 'customer_analytics',
  namespace: 'data_pipeline',
  version: '1.0.0',
  context: {
    date_range: {
      start_date: 30.days.ago.strftime('%Y-%m-%d'),
      end_date: Date.current.strftime('%Y-%m-%d')
    }
  }
)

task_id = Tasker::HandlerFactory.instance.run_task(task_request)
puts "Started task: #{task_id}"

# Monitor in real-time
loop do
  task = Tasker::Task.find(task_id)
  sequence = task.workflow_step_sequences.last
  
  puts "\n=== Pipeline Status: #{task.status} ==="
  sequence.steps.order(:created_at).each do |step|
    progress = step.annotations['progress_message'] || 'No progress info'
    duration = step.duration_ms ? "#{step.duration_ms/1000}s" : 'N/A'
    puts "#{step.name.ljust(25)} | #{step.status.ljust(10)} | #{duration.ljust(8)} | #{progress}"
  end
  
  break if ['completed', 'failed'].include?(task.status)
  sleep(5)
end
```

### 5. Business Logic Validation

**Objective**: Verify the generated insights make business sense

```ruby
# Get completed task results
task_id = "COMPLETED_TASK_ID"
task = Tasker::Task.find(task_id)
sequence = task.workflow_step_sequences.last
insights_step = sequence.steps.find { |s| s.name == 'generate_insights' }
insights = insights_step.result

# Validate executive summary
exec_summary = insights['executive_summary']
puts "Total Revenue: $#{exec_summary['period_overview']['total_revenue']}"
puts "Total Customers: #{exec_summary['period_overview']['total_customers_analyzed']}"
puts "VIP Customers: #{exec_summary['customer_highlights']['vip_customers_count']}"

# Validate customer insights
customer_insights = insights['customer_insights']
puts "Customers at Risk: #{customer_insights['churn_risk']['customers_at_risk']}"

# Validate product insights  
product_insights = insights['product_insights']
puts "Products Needing Reorder: #{product_insights['inventory']['reorder_needed_count']}"

# Validate recommendations
recommendations = insights['business_recommendations']
puts "Recommendations Generated: #{recommendations.length}"
recommendations.each do |rec|
  puts "- #{rec['title']} (#{rec['priority']} priority)"
end
```

### 6. Error Handling Tests

#### 6.1 Simulate Database Timeout

```ruby
# Temporarily modify extract_orders_handler.rb
# Add this code at the start of the process method:

def process(task, sequence, step)
  # Simulate timeout on first attempt
  if step.annotations['retry_attempt'].nil?
    step.annotations['retry_attempt'] = 1
    step.save!
    raise Tasker::RetryableError, "Simulated database timeout"
  end
  
  # Continue with normal processing...
```

**Expected**: Step retries automatically and succeeds on second attempt.

#### 6.2 Simulate CRM API Failure

```ruby
# In extract_users_handler.rb, modify fetch_users_from_crm method:

def fetch_users_from_crm(user_ids)
  # Simulate API failure
  retry_count = @retry_count ||= 0
  if retry_count < 2
    @retry_count = retry_count + 1
    raise Net::HTTPServerError, "CRM API temporarily unavailable"
  end
  
  # Normal processing...
```

**Expected**: CRM extraction retries up to 5 times as configured.

### 7. Performance Testing

#### 7.1 Large Dataset Test

```ruby
# Create larger dataset for stress testing
1000.times do |i|
  user = User.create!(
    email: "stress_test_#{i}@example.com",
    first_name: "User#{i}",
    # ... other fields
  )
  
  # Create orders for this user
  rand(1..5).times do
    order = Order.create!(customer_id: user.id, ...)
    # Add order items...
  end
end

# Run pipeline with larger dataset
task_request = Tasker::Types::TaskRequest.new(
  name: 'customer_analytics',
  namespace: 'data_pipeline',
  version: '1.0.0',
  context: {
    date_range: {
      start_date: 60.days.ago.strftime('%Y-%m-%d'),
      end_date: Date.current.strftime('%Y-%m-%d')
    },
    force_refresh: true
  }
)
```

#### 7.2 Memory Usage Monitoring

```ruby
# Monitor memory usage during processing
require 'benchmark'

def get_memory_usage
  `ps -o rss= -p #{Process.pid}`.to_i / 1024.0  # MB
end

puts "Starting memory: #{get_memory_usage} MB"

task_id = Tasker::HandlerFactory.instance.run_task(task_request)

# Monitor memory during execution
Thread.new do
  loop do
    task = Tasker::Task.find(task_id)
    puts "Memory: #{get_memory_usage} MB - Status: #{task.status}"
    break if ['completed', 'failed'].include?(task.status)
    sleep(10)
  end
end
```

### 8. Event System Testing

**Objective**: Verify event-driven monitoring works correctly

```ruby
# Check that events are being published
events_received = []

# Subscribe to events in a separate thread
Thread.new do
  Tasker::EventBus.subscribe do |event|
    if event[:namespace] == 'data_pipeline'
      events_received << {
        type: event[:type],
        step: event[:step_name],
        timestamp: Time.current
      }
      puts "Event received: #{event[:type]} - #{event[:step_name]}"
    end
  end
end

# Run pipeline
task_id = Tasker::HandlerFactory.instance.run_task(task_request)

# Wait for completion and check events
# Should see: step.started, step.completed for each step
# Plus: task.completed at the end
```

### 9. Cache Testing

**Objective**: Verify caching reduces redundant processing

```ruby
# Run pipeline twice with same date range
start_time = Time.current

# First run (no cache)
task_id_1 = Tasker::HandlerFactory.instance.run_task(task_request)
# Wait for completion...
first_duration = Time.current - start_time

# Second run (should use cache)
start_time = Time.current
task_id_2 = Tasker::HandlerFactory.instance.run_task(task_request)
# Wait for completion...
second_duration = Time.current - start_time

puts "First run: #{first_duration}s"
puts "Second run: #{second_duration}s"
puts "Speedup: #{(first_duration / second_duration).round(2)}x"

# Second run should be significantly faster due to caching
```

### 10. Force Refresh Testing

**Objective**: Verify force_refresh bypasses cache

```ruby
# Run with force_refresh: false (use cache)
task_request_cached = Tasker::Types::TaskRequest.new(
  name: 'customer_analytics',
  namespace: 'data_pipeline',
  version: '1.0.0',
  context: {
    date_range: {
      start_date: 7.days.ago.strftime('%Y-%m-%d'),
      end_date: Date.current.strftime('%Y-%m-%d')
    },
    force_refresh: false
  }
)

# Run with force_refresh: true (bypass cache)
task_request_fresh = task_request_cached.dup
task_request_fresh.context['force_refresh'] = true

# Compare execution times and verify different results if data changed
```

## Troubleshooting

### Common Issues

**Pipeline doesn't start:**
- Check Sidekiq is running: `ps aux | grep sidekiq`
- Verify Redis is running: `redis-cli ping`
- Check Rails logs: `tail -f log/development.log`

**Steps fail with "handler not found":**
- Restart Rails server to reload classes
- Verify file paths match class names exactly
- Check YAML configuration syntax

**Database connection errors:**
- Verify PostgreSQL is running
- Check `config/database.yml` credentials
- Run `rails db:migrate` if needed

**Memory issues with large datasets:**
- Reduce batch sizes in step handlers
- Monitor memory usage during processing
- Consider processing smaller date ranges

### Debug Commands

```ruby
# Check handler registration
Tasker::HandlerFactory.instance.handlers.keys

# Inspect task details
task = Tasker::Task.find(task_id)
task.context
task.status
task.workflow_step_sequences.last.steps.map { |s| [s.name, s.status] }

# Check step results
step = task.workflow_step_sequences.last.steps.find { |s| s.name == 'extract_orders' }
step.result
step.annotations

# Verify event subscribers
Tasker::EventSubscriber::Registry.instance.subscribers.keys
```

## Success Criteria

A successful test run should demonstrate:

✅ **Parallel Processing**: Extraction steps start simultaneously  
✅ **Dependency Management**: Transform steps wait for prerequisites  
✅ **Progress Tracking**: Real-time updates during processing  
✅ **Intelligent Retry**: Automatic recovery from transient failures  
✅ **Business Intelligence**: Actionable insights generated  
✅ **Event-Driven Monitoring**: Real-time notifications and alerts  
✅ **Performance**: Handles realistic data volumes efficiently  
✅ **Caching**: Reduces redundant processing between runs  

## Next Steps

After completing these tests:

1. **Customize for your domain** - Adapt customer segmentation and product analytics
2. **Add real integrations** - Replace mock APIs with actual services  
3. **Scale the processing** - Test with production-sized datasets
4. **Implement advanced monitoring** - Add metrics and alerting
5. **Move to Chapter 3** - Microservices coordination patterns

---

*These patterns form the foundation for enterprise-scale data processing pipelines that handle millions of records reliably.*