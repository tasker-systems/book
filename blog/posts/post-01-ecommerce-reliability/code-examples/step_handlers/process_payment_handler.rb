module Ecommerce
  module StepHandlers
    class ProcessPaymentHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        payment_info = task.context['payment_info']
        cart_validation = step_results(sequence, 'validate_cart')
        
        amount_to_charge = cart_validation['total']
        
        # Validate payment amount matches cart total
        if payment_info['amount'] != amount_to_charge
          raise Tasker::NonRetryableError, 
            "Payment amount mismatch. Expected: #{amount_to_charge}, Provided: #{payment_info['amount']}"
        end
        
        # Process payment using payment simulator
        result = PaymentSimulator.charge(
          amount: amount_to_charge,
          payment_method: payment_info['token']
        )
        
        case result.status
        when :success
          {
            payment_id: result.id,
            amount_charged: result.amount,
            currency: result.currency,
            payment_method_type: result.payment_method_type,
            transaction_id: result.transaction_id,
            processed_at: Time.current.iso8601
          }
        when :insufficient_funds
          raise Tasker::NonRetryableError, "Payment declined: Insufficient funds"
        when :invalid_card
          raise Tasker::NonRetryableError, "Payment declined: Invalid card"
        when :gateway_timeout
          raise Tasker::RetryableError, "Payment gateway timeout - will retry"
        when :rate_limited
          raise Tasker::RetryableError, "Payment gateway rate limited - will retry"
        when :temporary_failure
          raise Tasker::RetryableError, "Temporary payment failure: #{result.error}"
        else
          raise Tasker::NonRetryableError, "Unknown payment error: #{result.error}"
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
