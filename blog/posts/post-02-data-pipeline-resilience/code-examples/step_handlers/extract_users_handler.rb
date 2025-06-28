module DataPipeline
  module StepHandlers
    class ExtractUsersHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        date_range = task.context['date_range']
        start_date = Date.parse(date_range['start_date'])
        end_date = Date.parse(date_range['end_date'])
        force_refresh = task.context['force_refresh'] || false
        
        # Check cache first unless force refresh
        cached_data = get_cached_extraction('users', start_date, end_date)
        return cached_data if cached_data && !force_refresh
        
        # Extract users who were active during the date range
        # (created accounts or placed orders)
        active_user_ids = get_active_user_ids(start_date, end_date)
        total_count = active_user_ids.length
        processed_count = 0
        
        users = []
        
        # Process in batches to avoid overwhelming the CRM API
        active_user_ids.each_slice(500) do |user_id_batch|
          begin
            # Simulate CRM API call with retry logic
            batch_users = fetch_users_from_crm(user_id_batch)
            
            user_data = batch_users.map do |user|
              {
                user_id: user['id'],
                email: user['email'],
                first_name: user['first_name'],
                last_name: user['last_name'],
                created_at: user['created_at'],
                last_login: user['last_login_at'],
                customer_since: user['created_at'],
                marketing_preferences: {
                  email_opt_in: user['email_marketing_opt_in'],
                  sms_opt_in: user['sms_marketing_opt_in']
                },
                demographics: {
                  age_range: user['age_range'],
                  location: {
                    city: user['city'],
                    state: user['state'],
                    country: user['country']
                  }
                }
              }
            end
            
            users.concat(user_data)
            processed_count += user_id_batch.length
            
            # Update progress for monitoring
            progress_percent = (processed_count.to_f / total_count * 100).round(1)
            update_progress_annotation(
              step, 
              "Processed #{processed_count}/#{total_count} users (#{progress_percent}%)"
            )
            
            # Rate limit to avoid overwhelming CRM API
            sleep(0.5)
            
          rescue Net::TimeoutError => e
            raise Tasker::RetryableError, "CRM API timeout: #{e.message}"
          rescue Net::HTTPServerError => e
            raise Tasker::RetryableError, "CRM API server error: #{e.message}"
          rescue StandardError => e
            Rails.logger.error "User extraction error: #{e.class} - #{e.message}"
            raise Tasker::RetryableError, "CRM extraction failed, will retry: #{e.message}"
          end
        end
        
        result = {
          users: users,
          total_count: users.length,
          date_range: {
            start_date: start_date.iso8601,
            end_date: end_date.iso8601
          },
          extracted_at: Time.current.iso8601,
          data_quality: {
            users_with_orders: users.count { |u| u[:user_id].in?(get_customer_ids_with_orders(start_date, end_date)) },
            avg_account_age_days: calculate_avg_account_age(users),
            marketing_opt_in_rate: users.count { |u| u[:marketing_preferences][:email_opt_in] } / users.length.to_f
          }
        }
        
        # Cache the result
        cache_extraction('users', start_date, end_date, result)
        
        result
      end
      
      private
      
      def get_active_user_ids(start_date, end_date)
        # Get users who placed orders or created accounts during the date range
        customer_ids_from_orders = Order.where(created_at: start_date..end_date)
                                      .distinct
                                      .pluck(:customer_id)
        
        new_user_ids = User.where(created_at: start_date..end_date)
                          .pluck(:id)
        
        (customer_ids_from_orders + new_user_ids).uniq.compact
      end
      
      def get_customer_ids_with_orders(start_date, end_date)
        Order.where(created_at: start_date..end_date)
             .distinct
             .pluck(:customer_id)
      end
      
      def fetch_users_from_crm(user_ids)
        # Simulate CRM API call
        # In real implementation, this would call external CRM service
        User.where(id: user_ids).map do |user|
          {
            'id' => user.id,
            'email' => user.email,
            'first_name' => user.first_name,
            'last_name' => user.last_name,
            'created_at' => user.created_at.iso8601,
            'last_login_at' => user.last_sign_in_at&.iso8601,
            'email_marketing_opt_in' => user.marketing_emails_enabled,
            'sms_marketing_opt_in' => user.sms_notifications_enabled,
            'age_range' => determine_age_range(user.date_of_birth),
            'city' => user.city,
            'state' => user.state,
            'country' => user.country || 'US'
          }
        end
      end
      
      def determine_age_range(date_of_birth)
        return 'unknown' unless date_of_birth
        
        age = Date.current.year - date_of_birth.year
        case age
        when 0..17 then 'under_18'
        when 18..24 then '18_24'
        when 25..34 then '25_34'
        when 35..44 then '35_44'
        when 45..54 then '45_54'
        when 55..64 then '55_64'
        else '65_plus'
        end
      end
      
      def calculate_avg_account_age(users)
        return 0 if users.empty?
        
        total_days = users.sum do |user|
          account_created = Date.parse(user[:created_at])
          (Date.current - account_created).to_i
        end
        
        total_days / users.length
      end
      
      def update_progress_annotation(step, message)
        step.annotations.merge!({
          progress_message: message,
          last_updated: Time.current.iso8601
        })
        step.save!
      end
      
      def get_cached_extraction(data_type, start_date, end_date)
        cache_key = "extraction:#{data_type}:#{start_date}:#{end_date}"
        Rails.cache.read(cache_key)
      end
      
      def cache_extraction(data_type, start_date, end_date, data)
        cache_key = "extraction:#{data_type}:#{start_date}:#{end_date}"
        Rails.cache.write(cache_key, data, expires_in: 6.hours)
      end
    end
  end
end