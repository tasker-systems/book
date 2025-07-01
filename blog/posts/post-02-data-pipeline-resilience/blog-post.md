# The Data Pipeline That Kept Everyone Awake

*How one team transformed their fragile ETL nightmare into a bulletproof data orchestration system*

---

## The 3 AM Text Message

Six months after solving their Black Friday checkout crisis, Sarah's team at GrowthCorp was feeling confident. Their reliable checkout workflow had handled the holiday rush flawlessly - zero manual interventions, automatic recovery from payment gateway hiccups, complete visibility into every transaction.

Then the business got ambitious.

"We need real-time customer analytics," announced the CEO during the Monday morning all-hands. "Every morning at 7 AM, I want to see yesterday's customer behavior, purchase patterns, and inventory insights on my dashboard."

Sarah's heart sank. She knew what was coming.

At 3:17 AM on Thursday, her phone lit up with the text every engineer dreads:

> **DataOps Alert**: Customer analytics pipeline failed
> **Impact**: No dashboard data for executive meeting
> **ETA**: Manual intervention required
> **On-call**: YOU

Sarah was the fourth engineer this month to get the 3 AM data pipeline alert. It had become a running joke in the team chat: "Who's turn is it to debug the nightly ETL?"

But it wasn't funny when you're the one staring at logs at 3 AM, trying to figure out which of the 47 interdependent data processing steps failed, and whether you need to reprocess 8 hours worth of customer transaction data before the executive team arrives at 9 AM.

## The Fragile Foundation

Here's what their original data pipeline looked like:

```ruby
class CustomerAnalyticsJob < ApplicationJob
  def perform
    # Step 1: Extract data from multiple sources
    orders = extract_orders_from_database
    users = extract_users_from_crm
    products = extract_products_from_inventory

    # Step 2: Transform and join data
    customer_metrics = calculate_customer_metrics(orders, users)
    product_metrics = calculate_product_metrics(orders, products)

    # Step 3: Generate insights
    insights = generate_business_insights(customer_metrics, product_metrics)

    # Step 4: Update dashboard
    DashboardService.update_metrics(insights)

    # Step 5: Send completion notification
    SlackNotifier.post_message("#data-team", "Analytics pipeline completed")
  rescue => e
    # When this fails, EVERYTHING needs to be rerun
    SlackNotifier.post_message("#data-team", "🚨 Pipeline failed: #{e.message}")
    raise
  end
end
```

**What could go wrong?** Everything.

- **CRM API times out at step 2**: Entire 6-hour process starts over
- **Database connection drops during metrics calculation**: All extractions wasted
- **Dashboard service is down**: Data processed but not displayed
- **Any step failure**: No visibility into progress, no partial recovery

During their worst incident, the pipeline failed 3 times in one night:
1. **11 PM**: CRM API timeout after 2 hours of processing
2. **1:30 AM**: Database lock timeout after reprocessing for 2.5 hours
3. **4:45 AM**: Out of memory during metrics calculation

Sarah spent the entire night manually restarting processes, watching logs, and explaining to increasingly frustrated executives why their dashboard was empty.

## The Reliable Alternative

After their data pipeline nightmare, Sarah's team rebuilt it as a resilient, observable workflow using the same Tasker patterns that had saved their checkout system.

The key insight was separating **business-critical operations** (step handlers) from **observability operations** (event subscribers):

- **Step Handlers**: Extract, transform, and load data - must succeed for the pipeline to complete
- **Event Subscribers**: Monitoring, alerting, analytics - failures don't block the main workflow

### The YAML Configuration

```yaml
# config/customer_analytics_handler.yaml
task_name: customer_analytics
namespace: data_pipeline
version: "2.0.0"
description: "Resilient customer analytics pipeline with parallel processing"

# Enterprise annotations for monitoring
annotations:
  team: "data-engineering"
  criticality: "high"
  sla_hours: 8
  dependencies: ["postgresql", "redis", "crm_api"]

# Parallel data extraction phase
step_templates:
  - name: extract_orders
    description: "Extract order data from transactional database"
    handler_class: "DataPipeline::StepHandlers::ExtractOrdersHandler"
    timeout_seconds: 1800  # 30 minutes
    max_retries: 3
    retry_backoff: exponential

  - name: extract_users
    description: "Extract user data from CRM system"
    handler_class: "DataPipeline::StepHandlers::ExtractUsersHandler"
    timeout_seconds: 1200  # 20 minutes - CRM can be flaky
    max_retries: 5
    retry_backoff: exponential

  - name: extract_products
    description: "Extract product data from inventory system"
    handler_class: "DataPipeline::StepHandlers::ExtractProductsHandler"
    timeout_seconds: 900   # 15 minutes
    max_retries: 3
    retry_backoff: exponential

  # Dependent transformations (wait for all extractions)
  - name: transform_customer_metrics
    description: "Calculate customer behavior metrics"
    handler_class: "DataPipeline::StepHandlers::TransformCustomerMetricsHandler"
    depends_on: ["extract_orders", "extract_users"]
    timeout_seconds: 2700  # 45 minutes
    max_retries: 2

  - name: transform_product_metrics
    description: "Calculate product performance metrics"
    handler_class: "DataPipeline::StepHandlers::TransformProductMetricsHandler"
    depends_on: ["extract_orders", "extract_products"]
    timeout_seconds: 1800  # 30 minutes
    max_retries: 2

  # Final aggregation and output
  - name: generate_insights
    description: "Generate business insights and recommendations"
    handler_class: "DataPipeline::StepHandlers::GenerateInsightsHandler"
    depends_on: ["transform_customer_metrics", "transform_product_metrics"]
    timeout_seconds: 1200  # 20 minutes

  - name: update_dashboard
    description: "Update executive dashboard with new metrics"
    handler_class: "DataPipeline::StepHandlers::UpdateDashboardHandler"
    depends_on: ["generate_insights"]
    max_retries: 3
    retry_backoff: exponential

  - name: send_notifications
    description: "Send completion notifications to stakeholders"
    handler_class: "DataPipeline::StepHandlers::SendNotificationsHandler"
    depends_on: ["update_dashboard"]
    max_retries: 5
    retry_backoff: exponential

# Custom events for this pipeline
custom_events:
  - name: "data_extraction_started"
    description: "Fired when any extraction step begins"
  - name: "data_extraction_completed"
    description: "Fired when extraction step completes with metrics"
  - name: "pipeline_milestone_reached"
    description: "Fired at key pipeline milestones"
```

### The Modern Task Handler

```ruby
# app/tasks/data_pipeline/customer_analytics_handler.rb
module DataPipeline
  class CustomerAnalyticsHandler < Tasker::ConfiguredTask
    def schema
      {
        type: 'object',
        properties: {
          date_range: {
            type: 'object',
            properties: {
              start_date: { type: 'string', format: 'date' },
              end_date: { type: 'string', format: 'date' }
            },
            required: ['start_date', 'end_date']
          },
          force_refresh: { type: 'boolean', default: false },
          notification_channels: {
            type: 'array',
            items: { type: 'string' },
            default: ['#data-team']
          },
          processing_mode: {
            type: 'string',
            enum: ['standard', 'high_memory', 'distributed'],
            default: 'standard'
          }
        },
        required: ['date_range']
      }
    end

    # Runtime behavior customization based on data volume
    def configure_runtime_behavior(context)
      date_range = context['date_range']
      start_date = Date.parse(date_range['start_date'])
      end_date = Date.parse(date_range['end_date'])
      days_span = (end_date - start_date).to_i + 1

      # Adjust timeouts and batch sizes based on date range
      if days_span > 30
        # Large date range - increase timeouts and enable distributed mode
        override_step_config('extract_orders', {
          timeout_seconds: 3600,  # 1 hour
          max_retries: 5
        })
        override_step_config('transform_customer_metrics', {
          timeout_seconds: 5400   # 90 minutes
        })
      elsif days_span > 7
        # Medium date range - moderate adjustments
        override_step_config('extract_orders', {
          timeout_seconds: 2700   # 45 minutes
        })
      end

      # High memory mode for large datasets
      if context['processing_mode'] == 'high_memory'
        add_annotation('memory_profile', 'high_memory_optimized')
        add_annotation('batch_size_multiplier', '2.0')
      end
    end
  end
end
```

Now let's look at how they implemented the intelligent step handlers with clear separation of concerns:

```ruby
# app/tasks/data_pipeline/step_handlers/extract_orders_handler.rb
module DataPipeline
  module StepHandlers
    class ExtractOrdersHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        date_range = task.context['date_range']
        start_date = Date.parse(date_range['start_date'])
        end_date = Date.parse(date_range['end_date'])

        # Fire custom event for monitoring
        publish_event('data_extraction_started', {
          step_name: 'extract_orders',
          date_range: date_range,
          estimated_records: estimate_record_count(start_date, end_date)
        })

        # Calculate total records for progress tracking
        total_count = Order.where(created_at: start_date..end_date).count
        processed_count = 0
        orders = []

        # Process in batches to avoid memory issues
        Order.where(created_at: start_date..end_date).find_in_batches(batch_size: batch_size) do |batch|
          begin
            batch_data = batch.map do |order|
              {
                order_id: order.id,
                customer_id: order.customer_id,
                total_amount: order.total_amount,
                order_date: order.created_at.iso8601,
                items: order.items.map { |item|
                  {
                    product_id: item.product_id,
                    quantity: item.quantity,
                    price: item.price
                  }
                }
              }
            end

            orders.concat(batch_data)
            processed_count += batch.size

            # Update progress annotation for monitoring
            update_progress(step, processed_count, total_count)

          rescue ActiveRecord::ConnectionTimeoutError => e
            # Log the error but let Tasker handle retries
            log_structured_error("Database connection timeout during order extraction", {
              error: e.message,
              batch_size: batch.size,
              processed_so_far: processed_count
            })
            raise e  # Let Tasker retry with backoff
          rescue StandardError => e
            log_structured_error("Order extraction error", {
              error: e.message,
              batch_size: batch.size,
              processed_so_far: processed_count
            })
            raise e  # Let Tasker handle retries
          end
        end

        result = {
          orders: orders,
          total_count: orders.length,
          date_range: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601
          },
          extracted_at: Time.current.iso8601,
          processing_stats: {
            batches_processed: (processed_count.to_f / batch_size).ceil,
            batch_size: batch_size
          }
        }

        # Fire completion event with metrics
        publish_event('data_extraction_completed', {
          step_name: 'extract_orders',
          records_extracted: orders.length,
          processing_time_seconds: step.duration_seconds,
          date_range: date_range
        })

        result
      end

      private

      def batch_size
        # Adjust batch size based on memory profile annotation
        base_size = 1000
        multiplier = task.annotations['batch_size_multiplier']&.to_f || 1.0
        (base_size * multiplier).to_i
      end

      def estimate_record_count(start_date, end_date)
        # Quick estimate without full count for monitoring
        sample_day = Order.where(created_at: start_date..start_date.end_of_day).count
        days_span = (end_date - start_date).to_i + 1
        sample_day * days_span
      end

      def update_progress(step, processed, total)
        progress_percent = (processed.to_f / total * 100).round(1)
        step.annotations.merge!({
          progress_message: "Processed #{processed}/#{total} orders (#{progress_percent}%)",
          progress_percent: progress_percent,
          last_updated: Time.current.iso8601
        })
        step.save!
      end

      def log_structured_error(message, context)
        Rails.logger.error({
          message: message,
          correlation_id: task.correlation_id,
          step_name: 'extract_orders',
          context: context
        }.to_json)
      end
    end
  end
end
```

## The Magic: Event-Driven Monitoring

The real game-changer was the event-driven monitoring system that gave the team complete visibility into their data pipeline. **Critically, these are event subscribers - they handle observability without blocking the main business logic:**

```ruby
# app/tasks/data_pipeline/pipeline_monitor.rb
module DataPipeline
  class PipelineMonitor < Tasker::EventSubscriber::Base
    # Subscribe to core Tasker events + custom pipeline events
    subscribe_to 'step.started', 'step.completed', 'step.failed',
                 'task.completed', 'task.failed',
                 'data_extraction_started', 'data_extraction_completed',
                 'pipeline_milestone_reached'

    def handle_step_started(event)
      return unless data_pipeline_task?(event)

      # These are observability actions - they don't block the pipeline
      safely_execute do
        notify_step_started(event)
        update_dashboard_progress(event)
        log_step_metrics(event)
      end
    end

    def handle_step_completed(event)
      return unless data_pipeline_task?(event)

      safely_execute do
        notify_step_completed(event)
        update_dashboard_progress(event)

        # Log extraction metrics for monitoring
        if extraction_step?(event[:step_name])
          log_extraction_metrics(event)
          check_extraction_thresholds(event)
        end
      end
    end

    def handle_step_failed(event)
      return unless data_pipeline_task?(event)

      safely_execute do
        severity = determine_failure_severity(event[:step_name], event[:error])

        case severity
        when :critical
          page_on_call_engineer(event)
          notify_stakeholders(event)
          create_incident_ticket(event)
        when :high
          notify_data_team(event)
          schedule_retry_notification(event)
        when :medium
          log_for_review(event)
        end

        # Always update monitoring dashboards
        update_failure_metrics(event)
      end
    end

    def handle_data_extraction_started(event)
      safely_execute do
        # Custom event handling for extraction monitoring
        DatadogAPI.increment('data_pipeline.extraction.started', 1, {
          step: event[:step_name],
          estimated_records: event[:estimated_records]
        })

        # Start extraction timeout monitoring
        schedule_extraction_timeout_check(event)
      end
    end

    def handle_data_extraction_completed(event)
      safely_execute do
        # Record extraction performance metrics
        DatadogAPI.gauge('data_pipeline.extraction.records_count',
                        event[:records_extracted], {
          step: event[:step_name],
          date: Date.current.strftime('%Y-%m-%d')
        })

        DatadogAPI.gauge('data_pipeline.extraction.duration_seconds',
                        event[:processing_time_seconds], {
          step: event[:step_name]
        })

        # Check if extraction volume is within expected ranges
        validate_extraction_volume(event)
      end
    end

    def handle_task_completed(event)
      return unless data_pipeline_task?(event)

      safely_execute do
        notify_pipeline_success(event)
        update_dashboard_status('completed')
        schedule_next_run(event)
        record_pipeline_completion_metrics(event)
      end
    end

    def handle_task_failed(event)
      return unless data_pipeline_task?(event)

      safely_execute do
        notify_pipeline_failure(event)
        update_dashboard_status('failed')
        create_incident_report(event)
        record_pipeline_failure_metrics(event)
      end
    end

    private

    # Critical: All monitoring operations are wrapped in safe execution
    # Event subscriber failures should NEVER impact the main pipeline
    def safely_execute
      yield
    rescue => e
      # Log the monitoring failure but don't raise
      Rails.logger.error({
        message: "Pipeline monitoring error - this does not affect pipeline execution",
        error: e.message,
        backtrace: e.backtrace.first(5),
        subscriber: self.class.name
      }.to_json)

      # Optionally send to error tracking
      Sentry.capture_exception(e) if defined?(Sentry)
    end

    def data_pipeline_task?(event)
      event[:namespace] == 'data_pipeline'
    end

    def extraction_step?(step_name)
      step_name.start_with?('extract_')
    end

    def determine_failure_severity(step_name, error)
      case step_name
      when 'extract_orders', 'extract_users'
        # Core data failures are critical - business can't function without this data
        :critical
      when 'transform_customer_metrics', 'transform_product_metrics'
        # Processing failures are high priority - analytics are important
        :high
      when 'update_dashboard', 'send_notifications'
        # Output failures are medium priority - data exists, just not displayed
        :medium
      else
        :medium
      end
    end

    def notify_step_started(event)
      SlackAPI.post_message(
        channel: '#data-pipeline-status',
        text: "🔄 Starting: #{event[:step_name]} (#{event[:task_id]})",
        correlation_id: event[:correlation_id]
      )
    end

    def notify_step_completed(event)
      duration = event[:duration_seconds] || 0
      duration_text = duration > 60 ? "#{(duration/60).round(1)}min" : "#{duration.round(1)}s"

      SlackAPI.post_message(
        channel: '#data-pipeline-status',
        text: "✅ Completed: #{event[:step_name]} in #{duration_text}",
        correlation_id: event[:correlation_id]
      )
    end

    def page_on_call_engineer(event)
      PagerDutyAPI.trigger_incident(
        summary: "Critical data pipeline failure: #{event[:step_name]}",
        details: {
          step: event[:step_name],
          error: event[:error],
          task_id: event[:task_id],
          correlation_id: event[:correlation_id],
          timestamp: event[:timestamp]
        },
        urgency: 'high'
      )
    end

    def notify_stakeholders(event)
      # Notify business stakeholders about data availability
      SlackAPI.post_message(
        channel: '#executive-alerts',
        text: "⚠️ Customer analytics may be delayed due to pipeline failure. Engineering team investigating.",
        correlation_id: event[:correlation_id]
      )
    end

    def update_dashboard_progress(event)
      DashboardAPI.update_pipeline_status({
        task_id: event[:task_id],
        current_step: event[:step_name],
        status: event[:type],
        correlation_id: event[:correlation_id],
        last_updated: Time.current.iso8601
      })
    end

    def log_extraction_metrics(event)
      result = event[:result] || {}

      DatadogAPI.gauge('data_pipeline.extraction.records_count',
                      result['total_count'] || 0, {
        step: event[:step_name],
        date: Date.current.strftime('%Y-%m-%d')
      })

      DatadogAPI.gauge('data_pipeline.extraction.duration_seconds',
                      event[:duration_seconds] || 0, {
        step: event[:step_name]
      })
    end

    def schedule_next_run(event)
      # Schedule next day's pipeline run
      CustomerAnalyticsJob.set(wait_until: tomorrow_at_1am).perform_later({
        date_range: {
          start_date: Date.current.strftime('%Y-%m-%d'),
          end_date: Date.current.strftime('%Y-%m-%d')
        }
      })
    end

    def tomorrow_at_1am
      Date.current.tomorrow.beginning_of_day + 1.hour
    end

    def validate_extraction_volume(event)
      records_extracted = event[:records_extracted]
      step_name = event[:step_name]

      # Define expected ranges for each extraction step
      expected_ranges = {
        'extract_orders' => { min: 100, max: 50000 },
        'extract_users' => { min: 50, max: 10000 },
        'extract_products' => { min: 10, max: 5000 }
      }

      range = expected_ranges[step_name]
      return unless range

      if records_extracted < range[:min]
        SlackAPI.post_message(
          channel: '#data-quality-alerts',
          text: "⚠️ Low extraction volume: #{step_name} extracted only #{records_extracted} records (expected min: #{range[:min]})"
        )
      elsif records_extracted > range[:max]
        SlackAPI.post_message(
          channel: '#data-quality-alerts',
          text: "⚠️ High extraction volume: #{step_name} extracted #{records_extracted} records (expected max: #{range[:max]})"
        )
      end
    end
  end
end
```

## Real-Time Monitoring Dashboard

The team also built a real-time monitoring interface using Tasker's REST API:

```javascript
// Dashboard showing live pipeline progress
async function updatePipelineStatus() {
  try {
    const response = await fetch('/api/v1/tasks/current', {
      headers: { 'Authorization': `Bearer ${API_TOKEN}` }
    });
    const tasks = await response.json();

    const pipelineTask = tasks.data.find(task =>
      task.namespace === 'data_pipeline' &&
      task.current_state === 'running'
    );

    if (pipelineTask) {
      displayPipelineProgress(pipelineTask);

      // Get detailed step information
      const stepsResponse = await fetch(`/api/v1/tasks/${pipelineTask.id}/steps`);
      const steps = await stepsResponse.json();
      displayStepDetails(steps.data);
    }
  } catch (error) {
    console.error('Failed to update pipeline status:', error);
  }
}

function displayPipelineProgress(task) {
  const progressContainer = document.getElementById('pipeline-progress');
  const completedSteps = task.workflow_steps.filter(step => step.current_state === 'completed').length;
  const totalSteps = task.workflow_steps.length;
  const progressPercent = (completedSteps / totalSteps) * 100;

  progressContainer.innerHTML = `
    <div class="pipeline-status">
      <h3>Customer Analytics Pipeline</h3>
      <div class="progress-bar">
        <div class="progress-fill" style="width: ${progressPercent}%"></div>
      </div>
      <p>${completedSteps}/${totalSteps} steps completed (${progressPercent.toFixed(1)}%)</p>
      <p>Correlation ID: ${task.correlation_id}</p>
      <p>Started: ${new Date(task.created_at).toLocaleString()}</p>
    </div>
  `;
}

// Update every 30 seconds
setInterval(updatePipelineStatus, 30000);
```

## The Results

**Before Tasker:**
- 3+ pipeline failures per week requiring manual intervention
- 6-8 hour recovery time when failures occurred
- No visibility into progress during long-running operations
- Complete restart required for any step failure
- 15% of executive dashboards showed stale data

**After Tasker:**
- 0.1% failure rate with automatic recovery
- 95% of failures recover automatically within retry limits
- Real-time progress tracking for all stakeholders
- Partial recovery from exact failure points
- 99.9% on-time dashboard delivery
- **Zero monitoring failures impact pipeline execution**

The pipeline that once kept everyone awake now runs silently in the background, with intelligent monitoring that only alerts when human intervention is truly needed.

## Key Architectural Insights

### 1. Separation of Concerns: Step Handlers vs Event Subscribers

**Step Handlers** (Business Logic):
- Extract data from sources
- Transform and process data
- Update critical systems
- **Must succeed** for workflow completion
- Failures trigger retries and escalation

**Event Subscribers** (Observability):
- Monitor pipeline progress
- Send notifications and alerts
- Update dashboards and metrics
- **Never block** the main workflow
- Failures are logged but don't affect pipeline

### 2. Design for Parallel Execution
Independent operations run concurrently, not sequentially. The three extraction steps run in parallel, dramatically reducing total pipeline time.

### 3. Intelligent Progress Tracking
Long-running operations provide real-time visibility into their progress through annotations and custom events.

### 4. Event-Driven Monitoring
Different failures trigger different response strategies - from immediate pages to next-day reviews.

### 5. Partial Recovery
When a step fails, only that step and its dependents need to rerun. Previous successful steps remain completed.

### 6. Configuration-Driven Behavior
YAML configuration allows runtime behavior changes without code deployment.

## Want to Try This Yourself?

The complete data pipeline workflow is available and can be running in your development environment in under 5 minutes:

```bash
# Clone the demo repository
git clone https://github.com/tasker-systems/tasker-examples.git
cd tasker-examples/data-pipeline-resilience

# One-line setup using Tasker's automated demo builder
./setup.sh

# Start the services
redis-server &
bundle exec sidekiq &
bundle exec rails server

# Run the analytics pipeline
curl -X POST http://localhost:3000/api/v1/tasks \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer your_api_token" \
  -d '{
    "task_name": "customer_analytics",
    "namespace": "data_pipeline",
    "context": {
      "date_range": {
        "start_date": "2024-01-01",
        "end_date": "2024-01-01"
      }
    }
  }'

# Monitor progress in real-time
curl -H "Authorization: Bearer your_api_token" \
  http://localhost:3000/api/v1/tasks/TASK_ID

# View step details
curl -H "Authorization: Bearer your_api_token" \
  http://localhost:3000/api/v1/tasks/TASK_ID/steps
```

## 📊 Performance Analytics Reveal the Hidden Bottlenecks (New in v1.0.0)

Six months after implementing the resilient data pipeline, Sarah's team discovered something surprising through Tasker's new analytics system:

```bash
# Analyze data pipeline performance
curl -H "Authorization: Bearer $API_TOKEN" \
  "https://growthcorp.com/tasker/analytics/bottlenecks?namespace=data_pipeline&period=24"
```

**Key insights:**
- Extract operations run in perfect parallel (15-20 minutes each)
- Transform steps occasionally timeout during high-data periods (95th percentile: 2.1 hours)
- The `transform_customer_metrics` step has a 3.2% retry rate
- **Discovery:** Adding more memory to transform processes reduced duration by 40%

**Before analytics:** They assumed network issues caused most retries  
**After analytics:** Memory pressure was the real culprit

This data-driven insight led to right-sizing their infrastructure and eliminating weekend pipeline failures.

In our next post, we'll tackle an even more complex challenge: "Microservices Orchestration Without the Chaos" - when your simple user registration involves 6 API calls across 4 different services.

---

*Have you been woken up by data pipeline failures? Share your ETL horror stories in the comments below.*
