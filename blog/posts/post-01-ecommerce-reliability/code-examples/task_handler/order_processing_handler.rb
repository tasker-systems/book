module Ecommerce
  class OrderProcessingHandler < Tasker::TaskHandler::Base
    TASK_NAME = 'process_order'
    NAMESPACE = 'ecommerce'
    VERSION = '1.0.0'
    
    register_handler(TASK_NAME, namespace_name: NAMESPACE, version: VERSION)
    
    define_step_templates do |templates|
      templates.define(
        name: 'validate_cart',
        description: 'Validate cart items and calculate totals',
        handler_class: 'Ecommerce::StepHandlers::ValidateCartHandler',
        retryable: true,
        retry_limit: 3
      )
      
      templates.define(
        name: 'process_payment',
        description: 'Charge payment method',
        depends_on_step: 'validate_cart',
        handler_class: 'Ecommerce::StepHandlers::ProcessPaymentHandler',
        retryable: true,
        retry_limit: 3,
        timeout: 30.seconds
      )
      
      templates.define(
        name: 'update_inventory',
        description: 'Update inventory levels',
        depends_on_step: 'process_payment',
        handler_class: 'Ecommerce::StepHandlers::UpdateInventoryHandler',
        retryable: true,
        retry_limit: 2
      )
      
      templates.define(
        name: 'create_order',
        description: 'Create order record',
        depends_on_step: 'update_inventory',
        handler_class: 'Ecommerce::StepHandlers::CreateOrderHandler'
      )
      
      templates.define(
        name: 'send_confirmation',
        description: 'Send order confirmation email',
        depends_on_step: 'create_order',
        handler_class: 'Ecommerce::StepHandlers::SendConfirmationHandler',
        retryable: true,
        retry_limit: 5  # Email delivery can be flaky
      )
    end
    
    def schema
      {
        type: 'object',
        required: ['cart_items', 'payment_info', 'customer_info'],
        properties: {
          cart_items: {
            type: 'array',
            items: {
              type: 'object',
              required: ['product_id', 'quantity'],
              properties: {
                product_id: { type: 'integer' },
                quantity: { type: 'integer', minimum: 1 },
                price: { type: 'number', minimum: 0 }
              }
            }
          },
          payment_info: {
            type: 'object',
            required: ['token', 'amount'],
            properties: {
              token: { type: 'string', minLength: 1 },
              amount: { type: 'number', minimum: 0 }
            }
          },
          customer_info: {
            type: 'object',
            required: ['email', 'name'],
            properties: {
              email: { type: 'string', format: 'email' },
              name: { type: 'string', minLength: 1 },
              phone: { type: 'string' }
            }
          }
        }
      }
    end
    
    # Override to provide enhanced error context for e-commerce workflows
    def initialize_task!(task_request)
      task = super(task_request)
      
      # Add e-commerce specific context
      task.annotations.merge!({
        workflow_type: 'ecommerce_checkout',
        started_at: Time.current.iso8601,
        environment: Rails.env
      })
      
      task
    end
    
    private
    
    # Helper method to extract step results
    def step_results(sequence, step_name)
      step = sequence.steps.find { |s| s.name == step_name }
      step&.result || {}
    end
  end
end
