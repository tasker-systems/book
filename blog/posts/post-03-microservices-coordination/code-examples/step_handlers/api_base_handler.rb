module UserManagement
  module StepHandlers
    class ApiBaseHandler < Tasker::StepHandler::Base
      include CircuitBreakerPattern

      protected

      def http_client
        @http_client ||= HTTParty
      end

      def correlation_id
        @correlation_id ||= task.annotations['correlation_id'] || generate_correlation_id
      end

      def generate_correlation_id
        "reg_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
      end

      def default_headers
        {
          'Content-Type' => 'application/json',
          'Accept' => 'application/json',
          'X-Correlation-ID' => correlation_id,
          'X-Request-ID' => SecureRandom.uuid,
          'X-Source-Service' => 'tasker',
          'X-Workflow-ID' => task.id.to_s,
          'User-Agent' => "Tasker/#{Tasker::VERSION}"
        }
      end

      def handle_api_response(response, service_name)
        case response.code
        when 200..299
          # Success
          response.parsed_response
        when 400
          # Bad request - our fault, don't retry
          raise StandardError, "Bad request to #{service_name}: #{response.parsed_response}"
        when 401
          # Unauthorized - likely configuration issue
          raise StandardError, "Unauthorized request to #{service_name}. Check API credentials."
        when 403
          # Forbidden - don't retry
          raise StandardError, "Forbidden request to #{service_name}: #{response.parsed_response}"
        when 404
          # Not found - might be retryable if resource is being created
          nil  # Let calling method decide what to do
        when 409
          # Conflict - resource already exists
          response.parsed_response
        when 422
          # Unprocessable entity - validation failed
          raise StandardError, "Validation failed in #{service_name}: #{response.parsed_response}"
        when 429
          # Rate limited - definitely retry
          retry_after = response.headers['Retry-After']&.to_i || 60
          raise Tasker::RetryableError.new(
            "Rate limited by #{service_name}. Retry after #{retry_after} seconds",
            retry_after: retry_after
          )
        when 500..599
          # Server error - retry
          raise Tasker::RetryableError.new(
            "#{service_name} server error: #{response.code} - #{response.message}",
            retry_after: calculate_backoff
          )
        else
          # Unexpected response
          raise StandardError, "Unexpected response from #{service_name}: #{response.code} - #{response.body}"
        end
      end

      def calculate_backoff
        # Exponential backoff with jitter
        base = 2 ** (step.attempts || 0)
        jitter = rand(0..1000) / 1000.0
        [base + jitter, 30].min  # Cap at 30 seconds
      end

      def with_timeout(timeout_seconds = nil, &block)
        timeout = timeout_seconds || handler_timeout || 30
        Timeout.timeout(timeout) do
          yield
        end
      rescue Timeout::Error => e
        raise Tasker::RetryableError.new(
          "Request timed out after #{timeout} seconds",
          retry_after: calculate_backoff
        )
      end

      def handler_timeout
        # Get timeout from handler_config if available
        step&.step_template&.handler_config&.dig('timeout_seconds')
      end

      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.results || {}
      end

      def log_api_call(method, url, options = {})
        log_structured(:info, "API call initiated", {
          method: method.to_s.upcase,
          url: url,
          service: extract_service_name(url),
          correlation_id: correlation_id,
          timeout: options[:timeout],
          step_name: step.name
        })
      end

      def log_api_response(method, url, response, duration_ms)
        log_structured(:info, "API call completed", {
          method: method.to_s.upcase,
          url: url,
          service: extract_service_name(url),
          correlation_id: correlation_id,
          status_code: response.code,
          duration_ms: duration_ms,
          response_size: response.body&.bytesize,
          step_name: step.name
        })
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