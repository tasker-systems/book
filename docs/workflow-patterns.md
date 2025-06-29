# Workflow Patterns

> **Common workflow designs and when to use them**

This guide covers the most common workflow patterns you'll encounter when building with Tasker. Each pattern includes real-world use cases, implementation examples, and best practices.

## 1. Linear Workflow
*Sequential step execution*

**When to use**: Simple processes where each step must complete before the next begins.

**Use Cases**:
- User onboarding flows
- Document approval processes
- Order fulfillment pipelines
- Data transformation sequences

### Implementation

**YAML Configuration**:
```yaml
# config/tasker/tasks/onboarding/user_onboarding_handler.yaml
---
name: user_onboarding
namespace_name: onboarding
version: 1.0.0
task_handler_class: Onboarding::UserOnboardingHandler

step_templates:
  - name: create_account
  - name: send_welcome_email
    depends_on_step: create_account
  - name: setup_preferences
    depends_on_step: send_welcome_email
  - name: activate_trial
    depends_on_step: setup_preferences
```

**Handler Class**:
```ruby
module Onboarding
  class UserOnboardingHandler < Tasker::ConfiguredTask
    # Configuration driven by YAML file above
    # Add custom runtime behavior if needed

    def update_annotations(task, sequence, steps)
      # Track onboarding completion
      if steps.find { |s| s.name == 'activate_trial' }&.current_state == 'completed'
        task.annotations.create!(
          annotation_type: 'onboarding_completed',
          content: { completed_at: Time.current }
        )
      end
    end
  end
end
```

**Execution Flow**:
```
create_account → send_welcome_email → setup_preferences → activate_trial
```

**Benefits**:
- Simple to understand and debug
- Clear execution order
- Easy error handling

**Considerations**:
- Can be slow for independent operations
- Single point of failure stops entire flow
- Not optimal for parallel-capable work

---

## 2. Parallel Workflow
*Independent concurrent execution*

**When to use**: Multiple independent operations that can run simultaneously.

**Use Cases**:
- Data extraction from multiple sources
- Image/document processing
- Independent API calls
- Parallel validations

### Implementation

**YAML Configuration**:
```yaml
# config/tasker/tasks/data_processing/data_extraction_handler.yaml
---
name: data_extraction
namespace_name: data_processing
version: 1.0.0
task_handler_class: DataProcessing::DataExtractionHandler

step_templates:
  # All three extract steps run in parallel (no dependencies)
  - name: extract_orders
  - name: extract_customers
  - name: extract_products

  # Aggregation waits for all extractions
  - name: aggregate_data
    depends_on_step: ['extract_orders', 'extract_customers', 'extract_products']
```

**Handler Class**:
```ruby
module DataProcessing
  class DataExtractionHandler < Tasker::ConfiguredTask
    def establish_step_dependencies_and_defaults(task, steps)
      # Add runtime optimization based on data size
      if task.context['large_dataset']
        extract_steps = steps.select { |s| s.name.start_with?('extract_') }
        extract_steps.each { |step| step.update(timeout: 300000) } # 5 minute timeout
      end
    end
  end
end
```

**Execution Flow**:
```
┌─ extract_orders ───┐
├─ extract_customers ─┼─ aggregate_data
└─ extract_products ──┘
```

**Benefits**:
- Maximum parallelization
- Faster total execution time
- Independent failure isolation

**Considerations**:
- Resource contention possible
- Complex error handling
- Requires thread-safe operations

---

## 3. Diamond Pattern (Fan-out/Fan-in)
*Single input, parallel processing, single output*

**When to use**: One input needs multiple parallel validations or transformations before proceeding.

**Use Cases**:
- Order verification (credit, inventory, address)
- Multi-stage data validation
- Compliance checks
- Risk assessment workflows

### Implementation

**YAML Configuration**:
```yaml
# config/tasker/tasks/ecommerce/order_verification_handler.yaml
---
name: order_verification
namespace_name: ecommerce
version: 1.0.0
task_handler_class: Ecommerce::OrderVerificationHandler

step_templates:
  # Single entry point
  - name: validate_order_data

  # Fan out - parallel verifications (all depend on validation)
  - name: check_payment_method
    depends_on_step: validate_order_data
  - name: verify_shipping_address
    depends_on_step: validate_order_data
  - name: check_inventory_availability
    depends_on_step: validate_order_data

  # Fan in - wait for all verifications
  - name: finalize_order
    depends_on_step: ['check_payment_method', 'verify_shipping_address', 'check_inventory_availability']
```

**Handler Class**:
```ruby
module Ecommerce
  class OrderVerificationHandler < Tasker::ConfiguredTask
    def establish_step_dependencies_and_defaults(task, steps)
      # Add priority handling for urgent orders
      if task.context['priority'] == 'urgent'
        verification_steps = steps.select { |s| s.name.start_with?('check_') || s.name.start_with?('verify_') }
        verification_steps.each { |step| step.update(retry_limit: 1) } # Faster failure
      end
    end

    def update_annotations(task, sequence, steps)
      # Track verification results
      verification_results = steps.select { |s| s.name != 'validate_order_data' && s.name != 'finalize_order' }
                                  .map { |s| { s.name => s.current_state } }

      task.annotations.create!(
        annotation_type: 'verification_summary',
        content: { verifications: verification_results }
      )
    end
  end
end
```

**Execution Flow**:
```
                   ┌─ check_payment_method ────┐
validate_order_data ├─ verify_shipping_address ─┼─ finalize_order
                   └─ check_inventory_availability ┘
```

**Benefits**:
- Parallel verification/processing
- Single decision point
- Clear success/failure criteria

**Considerations**:
- All branches must succeed
- Complex state management
- Debugging can be challenging

---

## 4. Conditional Branching
*Dynamic workflow paths based on data*

**When to use**: Different processing paths based on input data or business rules.

**Use Cases**:
- Risk-based processing (high-value vs. standard orders)
- User type workflows (new vs. existing customers)
- Content moderation (automatic vs. manual review)
- Compliance workflows (different rules by region)

### Implementation

**YAML Configuration**:
```yaml
# config/tasker/tasks/ecommerce/conditional_order_handler.yaml
---
name: conditional_order_processing
namespace_name: ecommerce
version: 1.0.0
task_handler_class: Ecommerce::ConditionalOrderHandler

step_templates:
  - name: analyze_order

  # Conditional paths (step handler logic determines which executes)
  - name: standard_processing
    depends_on_step: analyze_order
  - name: manual_review
    depends_on_step: analyze_order
  - name: fraud_investigation
    depends_on_step: analyze_order
```

**Handler Class**:
```ruby
module Ecommerce
  class ConditionalOrderHandler < Tasker::ConfiguredTask
    def establish_step_dependencies_and_defaults(task, steps)
      # Conditional logic can be implemented in step handlers
      # or here based on task context
      analysis_result = task.context['analysis_result']

      case analysis_result&.dig('processing_path')
      when 'manual_review'
        # Disable other paths
        steps.find { |s| s.name == 'standard_processing' }&.update(enabled: false)
        steps.find { |s| s.name == 'fraud_investigation' }&.update(enabled: false)
      when 'fraud_investigation'
        steps.find { |s| s.name == 'standard_processing' }&.update(enabled: false)
        steps.find { |s| s.name == 'manual_review' }&.update(enabled: false)
      else
        # Standard processing
        steps.find { |s| s.name == 'manual_review' }&.update(enabled: false)
        steps.find { |s| s.name == 'fraud_investigation' }&.update(enabled: false)
      end
    end
  end
end

# Step handler determines the path
class AnalyzeOrderHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    order = Order.find(task.context['order_id'])

    processing_path = determine_processing_path(order)

    {
      order_value: order.total,
      risk_score: calculate_risk_score(order),
      processing_path: processing_path,
      requires_review: processing_path != 'standard'
    }
  end

  private

  def determine_processing_path(order)
    case
    when order.total > 10000
      'manual_review'
    when high_risk_indicators?(order)
      'fraud_investigation'
    else
      'standard_processing'
    end
  end
end
```

**Benefits**:
- Flexible business logic
- Optimized processing paths
- Business rule centralization

**Considerations**:
- Complex testing scenarios
- Path explosion possibility
- State management complexity

---

## 5. Pipeline Pattern
*Sequential data transformation*

**When to use**: Data flows through multiple transformation stages.

**Use Cases**:
- ETL data pipelines
- Image/video processing
- Document generation workflows
- Data enrichment processes

### Implementation

**YAML Configuration**:
```yaml
# config/tasker/tasks/data_processing/pipeline_handler.yaml
---
name: data_pipeline
namespace_name: data_processing
version: 1.0.0
task_handler_class: DataProcessing::PipelineHandler

step_templates:
  - name: extract_raw_data
  - name: clean_data
    depends_on_step: extract_raw_data
  - name: transform_data
    depends_on_step: clean_data
  - name: enrich_data
    depends_on_step: transform_data
  - name: validate_output
    depends_on_step: enrich_data
  - name: load_to_warehouse
    depends_on_step: validate_output
```

**Handler Class**:
```ruby
module DataProcessing
  class PipelineHandler < Tasker::ConfiguredTask
    def establish_step_dependencies_and_defaults(task, steps)
      # Configure timeouts based on data volume
      data_size = task.context['estimated_rows'] || 1000

      if data_size > 1_000_000
        # Large dataset - increase timeouts
        steps.each { |step| step.update(timeout: 600000) } # 10 minutes
      elsif data_size > 100_000
        # Medium dataset
        steps.each { |step| step.update(timeout: 300000) } # 5 minutes
      end
    end

    def update_annotations(task, sequence, steps)
      # Track pipeline metrics
      completed_steps = steps.select { |s| s.current_state == 'completed' }
      total_duration = completed_steps.sum { |s| s.duration || 0 }

      task.annotations.create!(
        annotation_type: 'pipeline_metrics',
        content: {
          total_duration_ms: total_duration,
          steps_completed: completed_steps.count,
          data_processed: task.context['estimated_rows']
        }
      )
    end
  end
end
```

**Benefits**:
- Clear data flow
- Easy to add/remove stages
- Individual stage optimization

**Considerations**:
- Memory management for large datasets
- Error propagation complexity
- Performance bottlenecks

---

## Pattern Selection Guide

### By Complexity

| Pattern | Complexity | Use When |
|---------|------------|----------|
| **Linear** | Low | Simple sequential processes |
| **Parallel** | Medium | Independent concurrent operations |
| **Diamond** | Medium | Single input, multiple validations |
| **Conditional** | High | Business rule-based branching |
| **Pipeline** | Medium | Data transformation sequences |

### By Performance

| Pattern | Throughput | Latency | Resource Usage |
|---------|------------|---------|----------------|
| **Linear** | Low | High | Low |
| **Parallel** | High | Low | High |
| **Diamond** | Medium | Medium | Medium |
| **Pipeline** | Medium | Medium | Medium |

### By Use Case

**Data Processing**: Pipeline, Parallel
**Business Workflows**: Linear, Diamond, Conditional
**Performance Critical**: Parallel
**Complex Validation**: Diamond

## Best Practices

### 1. **Start Simple**
Begin with linear workflows and add complexity only when needed:

```yaml
# Start with this - simple_order_handler.yaml
---
name: simple_order_processing
namespace_name: ecommerce
version: 1.0.0
task_handler_class: Ecommerce::SimpleOrderHandler

step_templates:
  - name: process_payment
  - name: send_confirmation
    depends_on_step: process_payment
```

```yaml
# Evolve to this when requirements grow - complex_order_handler.yaml
---
name: complex_order_processing
namespace_name: ecommerce
version: 2.0.0
task_handler_class: Ecommerce::ComplexOrderHandler

step_templates:
  - name: validate_order

  # Parallel validations
  - name: check_payment
    depends_on_step: validate_order
  - name: check_inventory
    depends_on_step: validate_order

  # Conditional processing (logic in handler class)
  - name: standard_processing
    depends_on_step: ['check_payment', 'check_inventory']
  - name: manual_review
    depends_on_step: ['check_payment', 'check_inventory']
```

```ruby
# Handler classes use ConfiguredTask
module Ecommerce
  class SimpleOrderHandler < Tasker::ConfiguredTask
    # Configuration driven by YAML
  end

  class ComplexOrderHandler < Tasker::ConfiguredTask
    def establish_step_dependencies_and_defaults(task, steps)
      # Add conditional logic for processing paths
      if task.context['requires_review']
        steps.find { |s| s.name == 'standard_processing' }&.update(enabled: false)
      else
        steps.find { |s| s.name == 'manual_review' }&.update(enabled: false)
      end
    end
  end
end
```

### 2. **Design for Failure**
Every pattern should handle failures gracefully:

```ruby
class ResilientStepHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    begin
      result = execute_operation(task)
      validate_result(result)
      result
    rescue TemporaryServiceError => e
      # Temporary failures - will retry based on step configuration
      Rails.logger.warn "Service temporarily unavailable, will retry: #{e.message}"
      raise e  # Let Tasker handle retries based on step configuration
    rescue InvalidDataError => e
      # Permanent failures - won't retry
      Rails.logger.error "Invalid input data: #{e.message}"
      raise StandardError, "Invalid input data: #{e.message}"
    rescue => e
      # Log unexpected errors for debugging
      Rails.logger.error "Unexpected error in #{step.name}: #{e.class} - #{e.message}"
      raise StandardError, "Unexpected error occurred"
    end
  end
end
```

### 3. **Monitor Performance**
Track execution metrics for each pattern using Tasker's enterprise observability:

```ruby
class PerformanceMonitor < Tasker::EventSubscriber::Base
  subscribe_to 'step.completed', 'step.retry_attempted', 'task.completed'

  def handle_step_completed(event)
    # Track step performance with correlation IDs
    Metrics.histogram('workflow.step.duration', event[:duration], {
      namespace: event[:namespace],
      step_name: event[:step_name],
      task_name: event[:task_name],
      correlation_id: event[:correlation_id]
    })

    # Alert on slow steps
    if event[:duration] > 30000  # 30 seconds
      SlackAPI.post_message(
        channel: '#performance-alerts',
        text: "Slow step detected: #{event[:step_name]} took #{event[:duration]}ms",
        metadata: {
          task_id: event[:task_id],
          correlation_id: event[:correlation_id],
          trace_id: event[:trace_id]
        }
      )
    end
  end

  def handle_step_retry_attempted(event)
    # Track retry patterns
    Metrics.increment('workflow.step.retries', {
      namespace: event[:namespace],
      step_name: event[:step_name],
      attempt_number: event[:attempt_number]
    })
  end

  def handle_task_completed(event)
    # Track overall workflow performance
    Metrics.histogram('workflow.task.total_duration', event[:total_duration], {
      namespace: event[:namespace],
      task_name: event[:task_name],
      step_count: event[:step_count]
    })
  end
end
```

**REST API Monitoring**:
```ruby
# Monitor via REST API
response = HTTParty.get("#{tasker_base_url}/tasker/tasks/#{task_id}")
task_data = JSON.parse(response.body)

puts "Task Status: #{task_data['current_state']}"
puts "Steps: #{task_data['workflow_steps'].map { |s| "#{s['name']}: #{s['current_state']}" }}"

# Health check endpoint
health_response = HTTParty.get("#{tasker_base_url}/tasker/health")
puts "Tasker Health: #{health_response.body}"
```

**OpenTelemetry Integration**:
```ruby
# Automatic tracing in step handlers
class MonitoredStepHandler < Tasker::StepHandler::Base
  def process(task, sequence, step)
    # Automatic span creation with Tasker's OpenTelemetry integration
    Tasker::Observability.trace("custom_business_operation") do |span|
      span.set_attribute('order_id', task.context['order_id'])
      span.set_attribute('customer_tier', task.context['customer_tier'])

      # Your business logic here
      result = perform_business_operation(task.context)

      span.set_attribute('operation_result', result['status'])
      result
    end
  end
end
```

### 4. **Test All Paths**
Comprehensive testing for complex patterns:

```ruby
RSpec.describe Ecommerce::ConditionalOrderHandler do
  describe 'path selection' do
    it 'routes high-value orders to manual review' do
      task_request = Tasker::Types::TaskRequest.new(
        name: 'conditional_order_processing',
        namespace: 'ecommerce',
        version: '1.0.0',
        context: { order_id: create(:high_value_order).id }
      )

      task_id = Tasker::HandlerFactory.instance.run_task(task_request)
      task = Tasker::Task.find(task_id)

      # Wait for completion
      wait_for_task_completion(task)

      completed_step_names = task.workflow_step_sequences.last.workflow_steps
                                .where(current_state: 'completed')
                                .pluck(:name)

      expect(completed_step_names).to include('manual_review')
      expect(completed_step_names).not_to include('standard_processing')
    end

    it 'routes standard orders to automatic processing' do
      task_request = Tasker::Types::TaskRequest.new(
        name: 'conditional_order_processing',
        namespace: 'ecommerce',
        version: '1.0.0',
        context: { order_id: create(:standard_order).id }
      )

      task_id = Tasker::HandlerFactory.instance.run_task(task_request)
      task = Tasker::Task.find(task_id)

      wait_for_task_completion(task)

      completed_step_names = task.workflow_step_sequences.last.workflow_steps
                                .where(current_state: 'completed')
                                .pluck(:name)

      expect(completed_step_names).to include('standard_processing')
      expect(completed_step_names).not_to include('manual_review')
    end
  end

  # Helper method for testing
  def wait_for_task_completion(task, timeout: 30.seconds)
    start_time = Time.current
    while task.current_state == 'running' && (Time.current - start_time) < timeout
      sleep 0.1
      task.reload
    end

    expect(task.current_state).to be_in(['completed', 'failed'])
  end
end

# API Testing
RSpec.describe 'Tasker REST API' do
  it 'provides task status via API' do
    task_request = Tasker::Types::TaskRequest.new(
      name: 'simple_order_processing',
      namespace: 'ecommerce',
      context: { order_id: 123 }
    )

    task_id = Tasker::HandlerFactory.instance.run_task(task_request)

    # Test REST API endpoint
    get "/tasker/tasks/#{task_id}"

    expect(response).to be_successful
    task_data = JSON.parse(response.body)
    expect(task_data['current_state']).to be_present
    expect(task_data['workflow_steps']).to be_an(Array)
  end
end
```

---

## Real-World Examples

See these patterns in action in our engineering stories:

### [Chapter 1: E-commerce Reliability](../blog/posts/post-01-ecommerce-reliability/)
**Patterns Used**: Linear workflow with error handling
- Simple checkout process with retry logic
- Clear step dependencies
- Production error handling

### [Chapter 2: Data Pipeline Resilience](../blog/posts/post-02-data-pipeline-resilience/)
**Patterns Used**: Diamond pattern with parallel extraction
- Parallel data extraction from multiple sources
- Fan-in aggregation for business insights
- Progress tracking for long-running operations

---

*Choose the right pattern for your use case, start simple, and evolve as your requirements grow. Each pattern has its place in building robust, maintainable workflows.*
