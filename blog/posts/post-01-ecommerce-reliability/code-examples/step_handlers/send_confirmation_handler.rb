module Ecommerce
  module StepHandlers
    class SendConfirmationHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        order_result = step_results(sequence, 'create_order')
        customer_info = task.context['customer_info']
        cart_validation = step_results(sequence, 'validate_cart')
        
        order_id = order_result['order_id']
        order_number = order_result['order_number']
        
        # Prepare email data
        email_data = {
          to: customer_info['email'],
          customer_name: customer_info['name'],
          order_number: order_number,
          order_id: order_id,
          total_amount: order_result['total_amount'],
          estimated_delivery: order_result['estimated_delivery'],
          items: cart_validation['validated_items'],
          order_url: "#{Rails.application.config.base_url}/orders/#{order_id}"
        }
        
        # Send confirmation email
        begin
          delivery_result = OrderMailer.confirmation_email(email_data).deliver_now
          
          # Log successful email delivery
          EmailLog.create!(
            order_id: order_id,
            email_type: 'order_confirmation',
            recipient: customer_info['email'],
            status: 'delivered',
            sent_at: Time.current,
            task_id: task.id
          )
          
          {
            email_sent: true,
            recipient: customer_info['email'],
            email_type: 'order_confirmation',
            sent_at: Time.current.iso8601,
            message_id: delivery_result.message_id
          }
        rescue Net::SMTPServerBusy => e
          raise Tasker::RetryableError, "SMTP server busy: #{e.message}"
        rescue Net::SMTPFatalError => e
          raise Tasker::NonRetryableError, "SMTP fatal error: #{e.message}"
        rescue Net::SMTPAuthenticationError => e
          raise Tasker::NonRetryableError, "SMTP authentication failed: #{e.message}"
        rescue Timeout::Error => e
          raise Tasker::RetryableError, "Email service timeout: #{e.message}"
        rescue StandardError => e
          # Log the error for debugging
          Rails.logger.error "Email delivery error: #{e.class} - #{e.message}"
          
          # Most email errors are retryable
          raise Tasker::RetryableError, "Email delivery failed: #{e.message}"
        end
      end
      
      private
      
      def step_results(sequence, step_name)
        step = sequence.steps.find { |s| s.name == step_name }
        step&.result || {}
      end
    end
  end
end
