# Testing Guide for E-commerce Reliability Example

This guide shows how to test the e-commerce workflow and demonstrate its reliability features.

## Quick Start

1. Set up the example:
```bash
cd /path/to/your/rails/app
./setup.sh
```

2. Load sample data:
```bash
rails runner 'SampleDataSetup.setup_all'
```

3. Start background jobs:
```bash
bundle exec sidekiq
```

## Testing Scenarios

### 1. Successful Checkout Flow

Test a normal, successful checkout:

```bash
curl -X POST http://localhost:3000/checkout \
  -H "Content-Type: application/json" \
  -d '{
    "checkout": {
      "cart_items": [
        {"product_id": 1, "quantity": 2},
        {"product_id": 3, "quantity": 1}
      ],
      "payment_info": {
        "token": "test_success_visa_4242424242424242",
        "amount": 294.97
      },
      "customer_info": {
        "email": "test@example.com",
        "name": "Test Customer",
        "phone": "555-123-4567"
      }
    }
  }'
```

Expected response:
```json
{
  "success": true,
  "task_id": "abc123",
  "status": "running",
  "checkout_url": "/order_status/abc123"
}
```

### 2. Payment Failure with Retry

Test payment failure scenarios:

```bash
# Insufficient funds (non-retryable)
curl -X POST http://localhost:3000/checkout \
  -H "Content-Type: application/json" \
  -d '{
    "checkout": {
      "cart_items": [{"product_id": 2, "quantity": 1}],
      "payment_info": {
        "token": "test_insufficient_funds",
        "amount": 29.98
      },
      "customer_info": {
        "email": "fail@example.com",
        "name": "Test Failure"
      }
    }
  }'

# Gateway timeout (retryable)
curl -X POST http://localhost:3000/checkout \
  -H "Content-Type: application/json" \
  -d '{
    "checkout": {
      "cart_items": [{"product_id": 4, "quantity": 1}],
      "payment_info": {
        "token": "test_timeout_slow_gateway",
        "amount": 48.19
      },
      "customer_info": {
        "email": "timeout@example.com",
        "name": "Timeout Test"
      }
    }
  }'
```

### 3. Inventory Conflict Scenario

Test what happens when inventory changes during checkout:

```bash
# Try to order more items than in stock
curl -X POST http://localhost:3000/checkout \
  -H "Content-Type: application/json" \
  -d '{
    "checkout": {
      "cart_items": [{"product_id": 5, "quantity": 100}],
      "payment_info": {
        "token": "test_success_mastercard",
        "amount": 8999.00
      },
      "customer_info": {
        "email": "inventory@example.com",
        "name": "Inventory Test"
      }
    }
  }'
```

## Monitoring Workflow Execution

### Check Task Status

```bash
# Replace TASK_ID with actual task ID from checkout response
curl http://localhost:3000/order_status/TASK_ID
```

Possible responses:
- `{"status": "processing", "current_step": "process_payment", "progress": {...}}`
- `{"status": "completed", "order_id": 123, "order_number": "ORD-20241215-ABC123"}`
- `{"status": "failed", "error": "Payment declined", "failed_step": "process_payment"}`

### View Detailed Workflow Information

```bash
curl http://localhost:3000/workflow_details/TASK_ID
```

This shows complete step-by-step execution details:
```json
{
  "task_id": "abc123",
  "status": "completed",
  "total_duration_ms": 2150,
  "steps": [
    {
      "name": "validate_cart",
      "status": "completed",
      "duration_ms": 45,
      "result": {"total": 294.97, "validated_items": [...]}
    },
    {
      "name": "process_payment", 
      "status": "completed",
      "duration_ms": 1200,
      "result": {"payment_id": "pi_abc123", "amount_charged": 294.97}
    }
  ]
}
```

### Retry Failed Workflows

```bash
# Retry a failed checkout
curl -X POST http://localhost:3000/retry_checkout/TASK_ID
```

## Rails Console Testing

For more detailed testing, use the Rails console:

```ruby
# Start a checkout workflow
task_request = Tasker::Types::TaskRequest.new(
  name: 'process_order',
  namespace: 'ecommerce', 
  version: '1.0.0',
  context: {
    cart_items: [{ product_id: 1, quantity: 2 }],
    payment_info: { token: 'test_success_visa', amount: 100.00 },
    customer_info: { email: 'console@example.com', name: 'Console Test' }
  }
)

task = Tasker::TaskExecutor.execute_async(task_request)

# Monitor progress
puts "Task ID: #{task.id}"
puts "Status: #{task.status}"

# Wait for completion (in console)
while task.reload.status == 'running'
  sleep 1
  puts "Current step: #{task.workflow_steps.running.first&.name}"
end

# View results
task.workflow_steps.each do |step|
  puts "#{step.name}: #{step.status} (#{step.duration}ms)"
  puts "  Result: #{step.result}" if step.completed?
  puts "  Error: #{step.error}" if step.failed?
end
```

## Testing Retry Logic

Simulate different failure scenarios and observe retry behavior:

```ruby
# Test payment retries
payment_tokens = [
  'test_timeout_slow_gateway',    # Will retry 3 times
  'test_rate_limit_api',          # Will retry with backoff
  'test_temp_fail_network',       # Will retry then succeed
  'test_insufficient_funds'       # Will fail immediately (non-retryable)
]

payment_tokens.each do |token|
  puts "Testing token: #{token}"
  
  task_request = Tasker::Types::TaskRequest.new(
    name: 'process_order',
    namespace: 'ecommerce',
    version: '1.0.0', 
    context: {
      cart_items: [{ product_id: 1, quantity: 1 }],
      payment_info: { token: token, amount: 50.00 },
      customer_info: { email: 'retry@example.com', name: 'Retry Test' }
    }
  )
  
  task = Tasker::TaskExecutor.execute_async(task_request)
  
  # Monitor until completion
  while ['running', 'pending'].include?(task.reload.status)
    sleep 0.5
  end
  
  payment_step = task.workflow_steps.find_by(name: 'process_payment')
  puts "  Result: #{task.status}"
  puts "  Retries: #{payment_step.retry_count}" if payment_step
  puts "  Error: #{payment_step.error}" if payment_step&.failed?
  puts ""
end
```

## Performance Testing

Test the workflow under load:

```ruby
# Create multiple concurrent checkouts
checkout_data = {
  cart_items: [{ product_id: 1, quantity: 1 }],
  payment_info: { token: 'test_success_visa', amount: 50.00 },
  customer_info: { email: 'load@example.com', name: 'Load Test' }
}

tasks = []
start_time = Time.current

10.times do |i|
  task_request = Tasker::Types::TaskRequest.new(
    name: 'process_order',
    namespace: 'ecommerce',
    version: '1.0.0',
    context: checkout_data.merge(
      customer_info: checkout_data[:customer_info].merge(
        email: "load#{i}@example.com"
      )
    )
  )
  
  tasks << Tasker::TaskExecutor.execute_async(task_request)
end

# Wait for all to complete
while tasks.any? { |t| ['running', 'pending'].include?(t.reload.status) }
  sleep 1
  completed = tasks.count { |t| t.status == 'completed' }
  failed = tasks.count { |t| t.status == 'failed' }
  puts "Completed: #{completed}, Failed: #{failed}, Running: #{tasks.length - completed - failed}"
end

end_time = Time.current
puts "Total time: #{(end_time - start_time).round(2)}s"

# Analyze results
successful_tasks = tasks.select { |t| t.status == 'completed' }
failed_tasks = tasks.select { |t| t.status == 'failed' }

puts "Success rate: #{(successful_tasks.length.to_f / tasks.length * 100).round(1)}%"
puts "Average duration: #{successful_tasks.map(&:duration).sum / successful_tasks.length}ms"
```

## Error Scenarios and Expected Behavior

| Scenario | Expected Behavior | Recovery |
|----------|------------------|----------|
| Payment gateway timeout | Retry 3 times with exponential backoff | Automatic |
| Insufficient funds | Fail immediately (non-retryable) | Manual customer action |
| Inventory out of stock | Retry 3 times in case of race conditions | Automatic or manual |
| Email delivery failure | Retry 5 times over increasing intervals | Automatic |
| Database connection lost | Retry with connection recovery | Automatic |
| Invalid payment token | Fail immediately (non-retryable) | Manual token refresh |

## Observing Retry Patterns

Watch retry behavior in real-time:

```ruby
# Monitor a specific task's retry attempts
task_id = "your_task_id_here"
task = Tasker::Task.find(task_id)

# Check retry counts for each step
task.workflow_steps.each do |step|
  puts "#{step.name}: #{step.retry_count} retries"
  
  if step.failed?
    puts "  Final error: #{step.error}"
    puts "  Last retry at: #{step.updated_at}"
  end
end

# Monitor step execution in real-time
loop do
  task.reload
  running_step = task.workflow_steps.running.first
  
  if running_step
    puts "Currently executing: #{running_step.name} (attempt ##{running_step.retry_count + 1})"
    sleep 2
  else
    puts "Task #{task.status}"
    break
  end
end
```

## Debugging Failed Workflows

When workflows fail, use these techniques to understand what happened:

```ruby
# Find recent failed tasks
failed_tasks = Tasker::Task.where(status: 'failed').recent.limit(10)

failed_tasks.each do |task|
  puts "Task #{task.id} failed:"
  
  # Find the failed step
  failed_step = task.workflow_steps.failed.first
  puts "  Failed step: #{failed_step.name}"
  puts "  Error: #{failed_step.error}"
  puts "  Retry attempts: #{failed_step.retry_count}"
  
  # Show the context that led to failure
  puts "  Task context: #{task.context}"
  
  # Show results from previous successful steps
  successful_steps = task.workflow_steps.completed
  successful_steps.each do |step|
    puts "  #{step.name} result: #{step.result}"
  end
  
  puts ""
end
```

This testing guide helps you understand how Tasker's reliability features work in practice and gives you confidence that your workflows will handle real-world failure scenarios gracefully.
