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
          },
          quality_thresholds: {
            type: 'object',
            properties: {
              min_customer_records: { type: 'integer', default: 100 },
              max_null_percentage: { type: 'number', default: 0.05 },
              min_order_records: { type: 'integer', default: 50 }
            }
          }
        },
        required: ['date_range']
      }
    end

    # Runtime behavior customization based on data volume and processing mode
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
        override_step_config('extract_users', {
          timeout_seconds: 2400   # 40 minutes
        })
        override_step_config('transform_customer_metrics', {
          timeout_seconds: 5400   # 90 minutes
        })
        override_step_config('transform_product_metrics', {
          timeout_seconds: 3600   # 60 minutes
        })
      elsif days_span > 7
        # Medium date range - moderate adjustments
        override_step_config('extract_orders', {
          timeout_seconds: 2700   # 45 minutes
        })
        override_step_config('extract_users', {
          timeout_seconds: 1800   # 30 minutes
        })
      end

      # Processing mode optimizations
      case context['processing_mode']
      when 'high_memory'
        add_annotation('memory_profile', 'high_memory_optimized')
        add_annotation('batch_size_multiplier', '2.0')
        add_annotation('parallel_workers', '4')
      when 'distributed'
        add_annotation('processing_mode', 'distributed')
        add_annotation('worker_pool_size', '8')
        add_annotation('memory_limit', '4GB')
      else
        add_annotation('processing_mode', 'standard')
        add_annotation('batch_size_multiplier', '1.0')
      end

      # Quality thresholds as annotations for step handlers
      if context['quality_thresholds']
        context['quality_thresholds'].each do |key, value|
          add_annotation("quality_threshold_#{key}", value.to_s)
        end
      end

      # Data pipeline specific annotations
      add_annotation('workflow_type', 'data_pipeline')
      add_annotation('pipeline_name', 'customer_analytics')
      add_annotation('data_version', '2.0.0')
      add_annotation('date_range_days', days_span.to_s)
      add_annotation('environment', Rails.env)
      add_annotation('force_refresh', context['force_refresh'].to_s)
    end

    # Custom validation for data pipeline context
    def validate_context(context)
      errors = super(context)

      # Validate date range
      if context['date_range']
        start_date = Date.parse(context['date_range']['start_date']) rescue nil
        end_date = Date.parse(context['date_range']['end_date']) rescue nil

        if start_date && end_date
          if start_date > end_date
            errors << "start_date cannot be after end_date"
          end

          if start_date > Date.current
            errors << "start_date cannot be in the future"
          end

          days_span = (end_date - start_date).to_i + 1
          if days_span > 365
            errors << "date range cannot exceed 365 days"
          end
        end
      end

      # Validate processing mode constraints
      if context['processing_mode'] == 'distributed'
        unless Rails.env.production?
          errors << "distributed processing mode only available in production"
        end
      end

      errors
    end
  end
end
