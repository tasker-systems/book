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
      
      # Quality gate
      templates.define(
        name: 'validate_data_quality',
        description: 'Validate data quality and completeness',
        depends_on_step: ['transform_customer_metrics', 'transform_product_metrics'],
        handler_class: 'DataPipeline::StepHandlers::ValidateDataQualityHandler',
        retryable: true,
        retry_limit: 2
      )
      
      # Final aggregation and output
      templates.define(
        name: 'generate_insights',
        description: 'Generate business insights and recommendations',
        depends_on_step: 'validate_data_quality',
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
            required: ['start_date', 'end_date'],
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
          },
          quality_thresholds: {
            type: 'object',
            properties: {
              min_customer_records: { type: 'integer', default: 100 },
              max_null_percentage: { type: 'number', default: 0.05 }
            }
          }
        }
      }
    end
    
    # Override to provide enhanced context for data pipeline workflows
    def initialize_task!(task_request)
      task = super(task_request)
      
      # Add data pipeline specific context
      task.annotations.merge!({
        workflow_type: 'data_pipeline',
        pipeline_name: 'customer_analytics',
        started_at: Time.current.iso8601,
        environment: Rails.env,
        data_version: '1.0.0'
      })
      
      task
    end
  end
end
