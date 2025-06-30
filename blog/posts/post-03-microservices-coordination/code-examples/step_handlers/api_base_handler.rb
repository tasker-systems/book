module UserManagement
  module StepHandlers
    class ApiBaseHandler < Tasker::StepHandler::Api
      include CircuitBreakerPattern

      # Initialize with microservices-specific configuration
      def initialize
        # Configure for JSON API microservices
        config = Tasker::StepHandler::Api::Config.new(
          url: 'http://localhost:3000', # Default - overridden by subclasses
          headers: enhanced_default_headers,
          enable_exponential_backoff: true,
          retry_delay: 1.0,
          jitter_factor: rand
        )
        
        super(config: config) do |conn|
          # Configure Faraday connection for microservices
          conn.request :json
          conn.response :json
          conn.adapter Faraday.default_adapter
          
          # Add custom middleware for circuit breaker integration
          conn.use CircuitBreakerMiddleware if defined?(CircuitBreakerMiddleware)
        end
      end

      protected

      # Override process_results to extract meaningful data from Faraday responses
      def process_results(step, process_output, initial_results)
        # If developer already set step.results, respect it
        return if step.results != initial_results

        # Transform Faraday::Response into meaningful data
        if process_output.is_a?(Faraday::Response)
          step.results = {
            status: process_output.status,
            body: process_output.body,
            headers: process_output.headers.to_h,
            success: process_output.success?
          }
        else
          # Use parent behavior for other response types
          super
        end
      end

      # Enhanced default headers with correlation tracking
      def enhanced_default_headers
        config.default_headers.merge(
          'X-Correlation-ID' => correlation_id,
          'X-Request-ID' => SecureRandom.uuid,
          'X-Source-Service' => 'tasker',
          'X-Workflow-ID' => current_task&.id&.to_s,
          'User-Agent' => "Tasker/#{Tasker::VERSION || '2.6.0'}"
        )
      end

      def correlation_id
        @correlation_id ||= current_task&.annotations&.dig('correlation_id') || generate_correlation_id
      end

      def generate_correlation_id
        "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
      end

      # Custom response handler that works with Faraday responses
      def handle_microservice_response(response, service_name)
        case response.status
        when 200..299
          # Success - return parsed body
          response.body
        when 400
          # Bad request - our fault, don't retry
          raise StandardError, "Bad request to #{service_name}: #{response.body}"
        when 401
          # Unauthorized - likely configuration issue
          raise StandardError, "Unauthorized request to #{service_name}. Check API credentials."
        when 403
          # Forbidden - don't retry
          raise StandardError, "Forbidden request to #{service_name}: #{response.body}"
        when 404
          # Not found - might be retryable if resource is being created
          nil  # Let calling method decide what to do
        when 409
          # Conflict - resource already exists, typically idempotent success
          response.body
        when 422
          # Unprocessable entity - validation failed
          raise StandardError, "Validation failed in #{service_name}: #{response.body}"
        when 429
          # Rate limited - let Tasker's built-in backoff handle this
          retry_after = response.headers['retry-after']&.to_i || 60
          raise Tasker::RetryableError.new(
            "Rate limited by #{service_name}. Retry after #{retry_after} seconds",
            retry_after: retry_after
          )
        when 500..599
          # Server error - let Tasker's built-in backoff handle this
          raise Tasker::RetryableError.new(
            "#{service_name} server error: #{response.status} - #{response.reason_phrase}",
            retry_after: config.retry_delay
          )
        else
          # Unexpected response
          raise StandardError, "Unexpected response from #{service_name}: #{response.status} - #{response.body}"
        end
      end

      # Access current task/step from method context (will be available during process())
      def current_task
        # This will be set by the framework during execution
        @current_task
      end

      def current_step
        @current_step
      end

      # Store task/step context when process is called
      def process(task, sequence, step)
        @current_task = task
        @current_step = step
        @current_sequence = sequence
        
        # Subclasses implement the actual API logic
        raise NotImplementedError, 'Subclasses must implement process method'
      end

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end

      def log_api_call(method, url, options = {})
        Rails.logger.info({
          message: "API call initiated",
          method: method.to_s.upcase,
          url: url,
          service: extract_service_name(url),
          correlation_id: correlation_id,
          timeout: options[:timeout],
          step_name: current_step&.name,
          task_id: current_task&.id
        }.to_json)
      end

      def log_api_response(method, url, response, duration_ms)
        status = response.respond_to?(:status) ? response.status : response.code
        body_size = response.respond_to?(:body) ? response.body&.bytesize : response.body&.bytesize
        
        Rails.logger.info({
          message: "API call completed",
          method: method.to_s.upcase,
          url: url,
          service: extract_service_name(url),
          correlation_id: correlation_id,
          status_code: status,
          duration_ms: duration_ms,
          response_size: body_size,
          step_name: current_step&.name,
          task_id: current_task&.id
        }.to_json)
      end

      def log_structured(level, message, context = {})
        full_context = {
          message: message,
          correlation_id: correlation_id,
          step_name: current_step&.name,
          task_id: current_task&.id,
          timestamp: Time.current.iso8601
        }.merge(context)
        
        Rails.logger.public_send(level, full_context.to_json)
      end

      def extract_service_name(url)
        uri = URI.parse(url)
        # Extract service name from hostname or path
        if uri.hostname&.include?('localhost')
          # Local development - extract from port or path
          case uri.port
          when 3001
            'user_service'
          when 3002
            'billing_service'
          when 3003
            'preferences_service'
          when 3004
            'notification_service'
          else
            uri.path.split('/')[1] || 'unknown_service'
          end
        else
          # Production - extract from subdomain or hostname
          uri.hostname&.split('.')&.first || 'unknown_service'
        end
      end
    end
  end
end
