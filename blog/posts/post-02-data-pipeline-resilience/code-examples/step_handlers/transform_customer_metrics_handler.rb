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
