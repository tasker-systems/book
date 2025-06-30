module UserManagement
  module StepHandlers
    class CreateUserAccountHandler < ApiBaseHandler
      def process(task, sequence, step)
        user_data = extract_user_data(task.context)
        service_url = user_service_url
        
        log_structured_info("Creating user account", {
          email: user_data[:email],
          plan: task.context['plan']
        })
        
        response = with_circuit_breaker('user_service') do
          with_timeout(30) do
            start_time = Time.current
            
            log_api_call(:post, "#{service_url}/users", timeout: 30)
            
            response = http_client.post("#{service_url}/users", {
              body: user_data.to_json,
              headers: default_headers,
              timeout: 30
            })
            
            duration_ms = ((Time.current - start_time) * 1000).to_i
            log_api_response(:post, "#{service_url}/users", response, duration_ms)
            
            response
          end
        end
        
        case response.code
        when 201
          # User created successfully
          user_data = response.parsed_response
          log_structured_info("User account created successfully", {
            user_id: user_data['id'],
            email: user_data['email']
          })
          
          {
            user_id: user_data['id'],
            email: user_data['email'],
            created_at: user_data['created_at'],
            correlation_id: correlation_id,
            service_response_time: response.headers['X-Response-Time'],
            status: 'created'
          }
          
        when 409
          # User already exists - check if it's the same user
          log_structured_info("User already exists, checking for idempotency", {
            email: user_data[:email]
          })
          
          existing_user = get_existing_user(user_data[:email])
          
          if existing_user && user_matches?(existing_user, user_data)
            log_structured_info("Existing user matches, treating as idempotent success", {
              user_id: existing_user['id']
            })
            
            {
              user_id: existing_user['id'],
              email: existing_user['email'],
              created_at: existing_user['created_at'],
              correlation_id: correlation_id,
              status: 'already_exists'
            }
          else
            raise StandardError, "User with email #{user_data[:email]} already exists with different data"
          end
          
        when 422
          # Validation error
          errors = response.parsed_response['errors'] || response.parsed_response['message']
          raise StandardError, "Invalid user data: #{errors}"
          
        else
          # Let base handler deal with other responses
          handle_api_response(response, 'user_service')
        end
        
      rescue CircuitOpenError => e
        # Circuit breaker is open
        log_structured_error("Circuit breaker open for user service", {
          error: e.message,
          service: 'user_service'
        })
        raise Tasker::RetryableError.new(e.message, retry_after: 60)
        
      rescue => e
        log_structured_error("Failed to create user account", {
          error: e.message,
          error_class: e.class.name,
          email: user_data[:email]
        })
        raise
      end
      
      private
      
      def extract_user_data(context)
        {
          email: context['email'],
          name: context['name'],
          phone: context['phone'],
          plan: context['plan'] || 'free',
          marketing_consent: context['marketing_consent'] || false,
          referral_code: context['referral_code'],
          source: context['source'] || 'web'
        }.compact
      end
      
      def get_existing_user(email)
        response = with_circuit_breaker('user_service') do
          with_timeout(15) do
            http_client.get("#{user_service_url}/users", {
              query: { email: email },
              headers: default_headers,
              timeout: 15
            })
          end
        end
        
        response.success? ? response.parsed_response : nil
      rescue => e
        log_structured_error("Failed to check existing user", {
          error: e.message,
          email: email
        })
        nil
      end
      
      def user_matches?(existing_user, new_user_data)
        # Check if core attributes match for idempotency
        existing_user &&
          existing_user['email'] == new_user_data[:email] &&
          existing_user['name'] == new_user_data[:name] &&
          existing_user['plan'] == new_user_data[:plan]
      end
      
      def user_service_url
        ENV.fetch('USER_SERVICE_URL', 'http://localhost:3001')
      end
      
      def log_structured_info(message, context = {})
        log_structured(:info, message, { step_name: 'create_user_account', service: 'user_service' }.merge(context))
      end
      
      def log_structured_error(message, context = {})
        log_structured(:error, message, { step_name: 'create_user_account', service: 'user_service' }.merge(context))
      end
    end
  end
end