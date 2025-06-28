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

```ruby
class UserOnboardingHandler < Tasker::TaskHandler::Base
  define_step_templates do |templates|
    templates.define(name: 'create_account')
    templates.define(name: 'send_welcome_email', depends_on_step: 'create_account')
    templates.define(name: 'setup_preferences', depends_on_step: 'send_welcome_email')
    templates.define(name: 'activate_trial', depends_on_step: 'setup_preferences')
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

```ruby
class DataExtractionHandler < Tasker::TaskHandler::Base
  define_step_templates do |templates|
    # All three extract steps run in parallel
    templates.define(name: 'extract_orders')
    templates.define(name: 'extract_customers')
    templates.define(name: 'extract_products')
    
    # Aggregation waits for all extractions
    templates.define(
      name: 'aggregate_data',
      depends_on_step: ['extract_orders', 'extract_customers', 'extract_products']
    )
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

```ruby
class OrderVerificationHandler < Tasker::TaskHandler::Base
  define_step_templates do |templates|
    # Single entry point
    templates.define(name: 'validate_order_data')
    
    # Fan out - parallel verifications
    templates.define(
      name: 'check_payment_method',
      depends_on_step: 'validate_order_data'
    )
    templates.define(
      name: 'verify_shipping_address',
      depends_on_step: 'validate_order_data'
    )
    templates.define(
      name: 'check_inventory_availability',
      depends_on_step: 'validate_order_data'
    )
    
    # Fan in - wait for all verifications
    templates.define(
      name: 'finalize_order',
      depends_on_step: ['check_payment_method', 'verify_shipping_address', 'check_inventory_availability']
    )
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

```ruby
class OrderProcessingHandler < Tasker::TaskHandler::Base
  define_step_templates do |templates|
    templates.define(name: 'analyze_order')
    
    # Conditional paths
    templates.define(
      name: 'standard_processing',
      depends_on_step: 'analyze_order'
    )
    templates.define(
      name: 'manual_review',
      depends_on_step: 'analyze_order'
    )
    templates.define(
      name: 'fraud_investigation',
      depends_on_step: 'analyze_order'
    )
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

```ruby
class DataPipelineHandler < Tasker::TaskHandler::Base
  define_step_templates do |templates|
    templates.define(name: 'extract_raw_data')
    templates.define(name: 'clean_data', depends_on_step: 'extract_raw_data')
    templates.define(name: 'transform_data', depends_on_step: 'clean_data')
    templates.define(name: 'enrich_data', depends_on_step: 'transform_data')
    templates.define(name: 'validate_output', depends_on_step: 'enrich_data')
    templates.define(name: 'load_to_warehouse', depends_on_step: 'validate_output')
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

```ruby
# Start with this
class SimpleOrderHandler < Tasker::TaskHandler::Base
  define_step_templates do |templates|
    templates.define(name: 'process_payment')
    templates.define(name: 'send_confirmation', depends_on_step: 'process_payment')
  end
end

# Evolve to this when requirements grow
class ComplexOrderHandler < Tasker::TaskHandler::Base
  define_step_templates do |templates|
    templates.define(name: 'validate_order')
    
    # Parallel validations
    templates.define(name: 'check_payment', depends_on_step: 'validate_order')
    templates.define(name: 'check_inventory', depends_on_step: 'validate_order')
    
    # Conditional processing
    templates.define(name: 'standard_processing', 
                   depends_on_step: ['check_payment', 'check_inventory'])
    templates.define(name: 'manual_review', 
                   depends_on_step: ['check_payment', 'check_inventory'])
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
      raise Tasker::RetryableError, "Service temporarily unavailable: #{e.message}"
    rescue InvalidDataError => e
      raise Tasker::PermanentError, "Invalid input data: #{e.message}"
    rescue => e
      # Log unexpected errors for debugging
      Rails.logger.error "Unexpected error in #{step.name}: #{e.class} - #{e.message}"
      raise Tasker::PermanentError, "Unexpected error occurred"
    end
  end
end
```

### 3. **Monitor Performance**
Track execution metrics for each pattern:

```ruby
class PerformanceMonitor < Tasker::EventSubscriber::Base
  subscribe_to 'step.completed'
  
  def handle_step_completed(event)
    # Track step performance
    Metrics.histogram('workflow.step.duration', event[:duration], {
      namespace: event[:namespace],
      step_name: event[:step_name],
      task_name: event[:task_name]
    })
    
    # Alert on slow steps
    if event[:duration] > 30000  # 30 seconds
      SlackAPI.post_message(
        channel: '#performance-alerts',
        text: "Slow step detected: #{event[:step_name]} took #{event[:duration]}ms"
      )
    end
  end
end
```

### 4. **Test All Paths**
Comprehensive testing for complex patterns:

```ruby
RSpec.describe ConditionalOrderHandler do
  describe 'path selection' do
    it 'routes high-value orders to manual review' do
      result = run_task_workflow('process_order', context: { 
        order_id: create(:high_value_order).id 
      })
      
      expect(result.completed_steps).to include('manual_review')
      expect(result.completed_steps).not_to include('standard_processing')
    end
    
    it 'routes standard orders to automatic processing' do
      result = run_task_workflow('process_order', context: { 
        order_id: create(:standard_order).id 
      })
      
      expect(result.completed_steps).to include('standard_processing')
      expect(result.completed_steps).not_to include('manual_review')
    end
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