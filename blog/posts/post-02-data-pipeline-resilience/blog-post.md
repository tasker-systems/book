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

After their data pipeline nightmare, Sarah's team rebuilt it as a resilient, observable workflow using the same Tasker patterns that had saved their checkout system:

```ruby
# app/tasks/data_pipeline/customer_analytics_handler.rb
module DataPipeline
  class CustomerAnalyticsHandler < Tasker::TaskHandler::Base
    TASK_NAME = 'customer_analytics'
    NAMESPACE = 'data_pipeline'
    VERSION = '1.0.0'
    
    register_handler(TASK_NAME, namespace_name: NAMESPACE, version: VERSION)
    
    define_step_templates do |templates|
      # Parallel data extraction (3 concurrent operations)
      templates.define(
        name: 'extract_orders',
        description: 'Extract order data from transactional database',
        handler_class: 'DataPipeline::StepHandlers::ExtractOrdersHandler',
        retryable: true,
        retry_limit: 3,
        timeout: 30.minutes
      )
      
      templates.define(
        name: 'extract_users',
        description: 'Extract user data from CRM system',
        handler_class: 'DataPipeline::StepHandlers::ExtractUsersHandler',
        retryable: true,
        retry_limit: 5,  # CRM can be flaky
        timeout: 20.minutes
      )
      
      templates.define(
        name: 'extract_products',
        description: 'Extract product data from inventory system',
        handler_class: 'DataPipeline::StepHandlers::ExtractProductsHandler',
        retryable: true,
        retry_limit: 3,
        timeout: 15.minutes
      )
      
      # Dependent transformations (wait for all extractions)
      templates.define(
        name: 'transform_customer_metrics',
        description: 'Calculate customer behavior metrics',
        depends_on_step: ['extract_orders', 'extract_users'],
        handler_class: 'DataPipeline::StepHandlers::TransformCustomerMetricsHandler',
        retryable: true,
        retry_limit: 2,
        timeout: 45.minutes
      )
      
      templates.define(
        name: 'transform_product_metrics',
        description: 'Calculate product performance metrics',
        depends_on_step: ['extract_orders', 'extract_products'],
        handler_class: 'DataPipeline::StepHandlers::TransformProductMetricsHandler',
        retryable: true,
        retry_limit: 2,
        timeout: 30.minutes
      )
      
      # Final aggregation and output
      templates.define(
        name: 'generate_insights',
        description: 'Generate business insights and recommendations',
        depends_on_step: ['transform_customer_metrics', 'transform_product_metrics'],
        handler_class: 'DataPipeline::StepHandlers::GenerateInsightsHandler',
        timeout: 20.minutes
      )
      
      templates.define(
        name: 'update_dashboard',
        description: 'Update executive dashboard with new metrics',
        depends_on_step: 'generate_insights',
        handler_class: 'DataPipeline::StepHandlers::UpdateDashboardHandler',
        retryable: true,
        retry_limit: 3
      )
      
      templates.define(
        name: 'send_notifications',
        description: 'Send completion notifications to stakeholders',
        depends_on_step: 'update_dashboard',
        handler_class: 'DataPipeline::StepHandlers::SendNotificationsHandler',
        retryable: true,
        retry_limit: 5
      )
    end
    
    def schema
      {
        type: 'object',
        properties: {
          date_range: {
            type: 'object',
            properties: {
              start_date: { type: 'string', format: 'date' },
              end_date: { type: 'string', format: 'date' }
            }
          },
          force_refresh: { type: 'boolean', default: false },
          notification_channels: {
            type: 'array',
            items: { type: 'string' },
            default: ['#data-team']
          }
        }
      }
    end
  end
end
```

Now let's look at how they implemented the intelligent step handlers with progress tracking:

```ruby
# app/tasks/data_pipeline/step_handlers/extract_orders_handler.rb
module DataPipeline
  module StepHandlers
    class ExtractOrdersHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        date_range = task.context['date_range']
        start_date = Date.parse(date_range['start_date'])
        end_date = Date.parse(date_range['end_date'])
        
        # Calculate total records for progress tracking
        total_count = Order.where(created_at: start_date..end_date).count
        processed_count = 0
        
        orders = []
        
        # Process in batches to avoid memory issues
        Order.where(created_at: start_date..end_date).find_in_batches(batch_size: 1000) do |batch|
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
            
            # Update progress for monitoring
            progress_percent = (processed_count.to_f / total_count * 100).round(1)
            update_progress_annotation(
              step, 
              "Processed #{processed_count}/#{total_count} orders (#{progress_percent}%)"
            )
            
          rescue ActiveRecord::ConnectionTimeoutError => e
            raise Tasker::RetryableError, "Database connection timeout: #{e.message}"
          rescue StandardError => e
            Rails.logger.error "Order extraction error: #{e.message}"
            raise Tasker::RetryableError, "Extraction failed, will retry: #{e.message}"
          end
        end
        
        {
          orders: orders,
          total_count: orders.length,
          date_range: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601
          },
          extracted_at: Time.current.iso8601
        }
      end
      
      private
      
      def update_progress_annotation(step, message)
        step.annotations.merge!({
          progress_message: message,
          last_updated: Time.current.iso8601
        })
        step.save!
      end
    end
  end
end
```

```ruby
# app/tasks/data_pipeline/step_handlers/transform_customer_metrics_handler.rb
module DataPipeline
  module StepHandlers
    class TransformCustomerMetricsHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        orders_data = step_results(sequence, 'extract_orders')
        users_data = step_results(sequence, 'extract_users')
        
        orders = orders_data['orders']
        users = users_data['users']
        
        # Create lookup hash for efficient user data access
        users_by_id = users.index_by { |user| user['user_id'] }
        
        # Group orders by customer
        orders_by_customer = orders.group_by { |order| order['customer_id'] }
        
        customer_metrics = []
        processed_customers = 0
        total_customers = orders_by_customer.keys.length
        
        orders_by_customer.each do |customer_id, customer_orders|
          user_info = users_by_id[customer_id]
          next unless user_info  # Skip if user data missing
          
          metrics = calculate_customer_metrics(customer_orders, user_info)
          customer_metrics << metrics
          
          processed_customers += 1
          
          # Update progress every 100 customers
          if processed_customers % 100 == 0
            progress_percent = (processed_customers.to_f / total_customers * 100).round(1)
            update_progress_annotation(
              step,
              "Processed #{processed_customers}/#{total_customers} customers (#{progress_percent}%)"
            )
          end
        end
        
        {
          customer_metrics: customer_metrics,
          total_customers: customer_metrics.length,
          metrics_calculated: %w[
            total_lifetime_value
            average_order_value
            order_frequency
            days_since_last_order
            customer_segment
          ],
          calculated_at: Time.current.iso8601
        }
      end
      
      private
      
      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.result || {}
      end
      
      def calculate_customer_metrics(customer_orders, user_info)
        total_spent = customer_orders.sum { |order| order['total_amount'] }
        order_count = customer_orders.length
        avg_order_value = order_count > 0 ? total_spent / order_count : 0
        
        last_order_date = customer_orders.map { |order| Date.parse(order['order_date']) }.max
        days_since_last_order = last_order_date ? (Date.current - last_order_date).to_i : nil
        
        {
          customer_id: user_info['user_id'],
          customer_email: user_info['email'],
          total_lifetime_value: total_spent,
          average_order_value: avg_order_value.round(2),
          total_orders: order_count,
          order_frequency: calculate_order_frequency(customer_orders),
          days_since_last_order: days_since_last_order,
          customer_segment: determine_customer_segment(total_spent, order_count),
          acquisition_date: user_info['created_at'],
          calculated_at: Time.current.iso8601
        }
      end
      
      def calculate_order_frequency(orders)
        return 0 if orders.length < 2
        
        order_dates = orders.map { |order| Date.parse(order['order_date']) }.sort
        total_days = order_dates.last - order_dates.first
        
        return 0 if total_days <= 0
        
        (orders.length - 1) / (total_days / 30.0)  # Orders per month
      end
      
      def determine_customer_segment(total_spent, order_count)
        case
        when total_spent >= 1000 && order_count >= 10
          'VIP'
        when total_spent >= 500 || order_count >= 5
          'Regular'
        when total_spent >= 100 || order_count >= 2
          'Occasional'
        else
          'New'
        end
      end
      
      def update_progress_annotation(step, message)
        step.annotations.merge!({
          progress_message: message,
          last_updated: Time.current.iso8601
        })
        step.save!
      end
    end
  end
end
```

## The Magic: Event-Driven Monitoring

The real game-changer was the event-driven monitoring system that gave the team complete visibility into their data pipeline:

```ruby
# app/tasks/data_pipeline/pipeline_monitor.rb
module DataPipeline
  class PipelineMonitor < Tasker::EventSubscriber::Base
    subscribe_to 'step.started', 'step.completed', 'step.failed', 'task.completed', 'task.failed'
    
    def handle_step_started(event)
      if data_pipeline_task?(event)
        notify_step_started(event)
        update_dashboard_progress(event)
      end
    end
    
    def handle_step_completed(event)
      if data_pipeline_task?(event)
        notify_step_completed(event)
        update_dashboard_progress(event)
        
        # Special handling for extraction steps
        if extraction_step?(event[:step_name])
          log_extraction_metrics(event)
        end
      end
    end
    
    def handle_step_failed(event)
      if data_pipeline_task?(event)
        severity = determine_failure_severity(event[:step_name], event[:error])
        
        case severity
        when :critical
          page_on_call_engineer(event)
          notify_stakeholders(event)
        when :high
          notify_data_team(event)
          schedule_retry_notification(event)
        when :medium
          log_for_review(event)
        end
      end
    end
    
    def handle_task_completed(event)
      if data_pipeline_task?(event)
        notify_pipeline_success(event)
        update_dashboard_status('completed')
        schedule_next_run(event)
      end
    end
    
    def handle_task_failed(event)
      if data_pipeline_task?(event)
        notify_pipeline_failure(event)
        update_dashboard_status('failed')
        create_incident_report(event)
      end
    end
    
    private
    
    def data_pipeline_task?(event)
      event[:namespace] == 'data_pipeline'
    end
    
    def extraction_step?(step_name)
      step_name.start_with?('extract_')
    end
    
    def determine_failure_severity(step_name, error)
      case step_name
      when 'extract_orders', 'extract_users'
        # Core data failures are critical
        :critical
      when 'transform_customer_metrics', 'transform_product_metrics'
        # Processing failures are high priority
        :high
      when 'update_dashboard', 'send_notifications'
        # Output failures are medium priority
        :medium
      else
        :medium
      end
    end
    
    def notify_step_started(event)
      SlackAPI.post_message(
        channel: '#data-pipeline-status',
        text: "🔄 Starting: #{event[:step_name]} (#{event[:task_id]})"
      )
    end
    
    def notify_step_completed(event)
      duration = event[:duration] || 0
      duration_text = duration > 60000 ? "#{(duration/60000).round(1)}min" : "#{(duration/1000).round(1)}s"
      
      SlackAPI.post_message(
        channel: '#data-pipeline-status',
        text: "✅ Completed: #{event[:step_name]} in #{duration_text}"
      )
    end
    
    def page_on_call_engineer(event)
      PagerDutyAPI.trigger_incident(
        summary: "Critical data pipeline failure: #{event[:step_name]}",
        details: {
          step: event[:step_name],
          error: event[:error],
          task_id: event[:task_id],
          timestamp: event[:timestamp]
        },
        urgency: 'high'
      )
    end
    
    def notify_stakeholders(event)
      # Notify business stakeholders about data availability
      SlackAPI.post_message(
        channel: '#executive-alerts',
        text: "⚠️ Customer analytics may be delayed due to pipeline failure. Engineering team investigating."
      )
    end
    
    def update_dashboard_progress(event)
      DashboardAPI.update_pipeline_status({
        task_id: event[:task_id],
        current_step: event[:step_name],
        status: event[:type],
        last_updated: Time.current.iso8601
      })
    end
    
    def log_extraction_metrics(event)
      result = event[:result] || {}
      
      DatadogAPI.gauge('data_pipeline.extraction.records_count', result['total_count'] || 0, {
        step: event[:step_name],
        date: Date.current.strftime('%Y-%m-%d')
      })
      
      DatadogAPI.gauge('data_pipeline.extraction.duration_seconds', (event[:duration] || 0) / 1000, {
        step: event[:step_name]
      })
    end
    
    def schedule_next_run(event)
      # Schedule next day's pipeline run
      CustomerAnalyticsJob.set(wait_until: tomorrow_at_midnight).perform_later({
        date_range: {
          start_date: Date.current.strftime('%Y-%m-%d'),
          end_date: Date.current.strftime('%Y-%m-%d')
        }
      })
    end
    
    def tomorrow_at_midnight
      Date.current.tomorrow.beginning_of_day + 1.hour  # 1 AM start time
    end
  end
end
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

The pipeline that once kept everyone awake now runs silently in the background, with intelligent monitoring that only alerts when human intervention is truly needed.

## Key Takeaways

1. **Design for parallel execution** - Independent operations should run concurrently, not sequentially

2. **Implement intelligent progress tracking** - Long-running operations need visibility into their progress

3. **Build event-driven monitoring** - Different failures need different response strategies

4. **Plan for partial recovery** - Don't restart entire processes when only one step fails

5. **Think in dependency graphs** - Data transformations have natural dependencies that should be explicit

6. **Make alerts actionable** - Distinguish between "page immediately" and "review tomorrow" failures

## Want to Try This Yourself?

The complete data pipeline workflow is available and can be running in your development environment in under 5 minutes:

```bash
# One-line setup using Tasker's install pattern
curl -fsSL https://raw.githubusercontent.com/jcoletaylor/tasker/main/blog-examples/data-pipeline-resilience/setup.sh | bash

# Start the services
cd data-pipeline-demo
redis-server &
bundle exec sidekiq &
bundle exec rails server

# Run the analytics pipeline
curl -X POST http://localhost:3000/analytics/start \
  -H "Content-Type: application/json" \
  -d '{"date_range": {"start_date": "2024-01-01", "end_date": "2024-01-01"}}'

# Monitor progress in real-time
curl http://localhost:3000/analytics/status/TASK_ID
```

In our next post, we'll tackle an even more complex challenge: "Microservices Orchestration Without the Chaos" - when your simple user registration involves 6 API calls across 4 different services.

---

*Have you been woken up by data pipeline failures? Share your ETL horror stories in the comments below.*
