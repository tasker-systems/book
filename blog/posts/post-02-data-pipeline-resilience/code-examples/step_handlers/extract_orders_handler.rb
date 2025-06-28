module DataPipeline
  module StepHandlers
    class ExtractOrdersHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        date_range = task.context['date_range']
        start_date = Date.parse(date_range['start_date'])
        end_date = Date.parse(date_range['end_date'])
        force_refresh = task.context['force_refresh'] || false
        
        # Check cache first unless force refresh
        cached_data = get_cached_extraction('orders', start_date, end_date)
        return cached_data if cached_data && !force_refresh
        
        # Calculate total records for progress tracking
        total_count = Order.where(created_at: start_date..end_date).count
        processed_count = 0
        
        orders = []
        
        # Process in batches to avoid memory issues
        Order.where(created_at: start_date..end_date)
             .includes(:order_items, :customer)
             .find_in_batches(batch_size: 1000) do |batch|
          begin
            batch_data = batch.map do |order|
              {
                order_id: order.id,
                customer_id: order.customer_id,
                customer_email: order.customer&.email,
                total_amount: order.total_amount,
                subtotal: order.subtotal,
                tax_amount: order.tax_amount,
                shipping_amount: order.shipping_amount,
                order_date: order.created_at.iso8601,
                status: order.status,
                payment_method: order.payment_method,
                items: order.order_items.map { |item|
                  {
                    product_id: item.product_id,
                    quantity: item.quantity,
                    unit_price: item.unit_price,
                    line_total: item.line_total,
                    category: item.product&.category
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
            
            # Yield control periodically to avoid blocking
            sleep(0.1) if processed_count % 5000 == 0
            
          rescue ActiveRecord::ConnectionTimeoutError => e
            raise Tasker::RetryableError, "Database connection timeout: #{e.message}"
          rescue ActiveRecord::StatementInvalid => e
            raise Tasker::RetryableError, "Database query error: #{e.message}"
          rescue StandardError => e
            Rails.logger.error "Order extraction error: #{e.class} - #{e.message}"
            raise Tasker::RetryableError, "Extraction failed, will retry: #{e.message}"
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
          data_quality: {
            records_with_items: orders.count { |o| o[:items].any? },
            avg_order_value: orders.sum { |o| o[:total_amount] } / orders.length.to_f,
            unique_customers: orders.map { |o| o[:customer_id] }.uniq.length
          }
        }
        
        # Cache the result
        cache_extraction('orders', start_date, end_date, result)
        
        result
      end
      
      private
      
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
