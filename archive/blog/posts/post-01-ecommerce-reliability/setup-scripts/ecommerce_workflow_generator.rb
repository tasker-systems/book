# Rails Generator for E-commerce Workflow
# Usage: rails generate ecommerce_workflow

class EcommerceWorkflowGenerator < Rails::Generators::Base
  source_root File.expand_path('templates', __dir__)
  
  def create_task_handler
    create_file "app/tasks/ecommerce/order_processing_handler.rb", task_handler_content
  end
  
  def create_step_handlers
    %w[validate_cart process_payment update_inventory create_order send_confirmation].each do |step|
      create_file "app/tasks/ecommerce/step_handlers/#{step}_handler.rb", 
                  step_handler_content(step)
    end
  end
  
  def create_models
    create_file "app/models/product.rb", product_model_content
    create_file "app/models/order.rb", order_model_content
    create_file "app/models/inventory_log.rb", inventory_log_model_content
    create_file "app/models/email_log.rb", email_log_model_content
  end
  
  def create_controller
    create_file "app/controllers/checkout_controller.rb", controller_content
  end
  
  def create_demo_files
    create_file "lib/demo/payment_simulator.rb", payment_simulator_content
    create_file "lib/demo/sample_data_setup.rb", sample_data_content
  end
  
  def create_routes
    route "post '/checkout', to: 'checkout#create_order'"
    route "get '/order_status/:task_id', to: 'checkout#order_status', as: 'order_status'"
    route "post '/retry_checkout/:task_id', to: 'checkout#retry_checkout', as: 'retry_checkout'"
    route "get '/workflow_details/:task_id', to: 'checkout#workflow_details', as: 'workflow_details'"
  end
  
  def create_config
    create_file "config/tasker/tasks/ecommerce/order_processing.yaml", yaml_config_content
  end
  
  def show_completion_message
    say "✅ E-commerce workflow generated successfully!", :green
    say ""
    say "Next steps:", :blue
    say "1. Run migrations: rails db:migrate"
    say "2. Load sample data: rails runner 'SampleDataSetup.setup_all'"
    say "3. Start Sidekiq: bundle exec sidekiq"
    say "4. Test the workflow:"
    say "   curl -X POST http://localhost:3000/checkout \\"
    say "     -H 'Content-Type: application/json' \\"
    say "     -d '{\"checkout\": {\"cart_items\": [{\"product_id\": 1, \"quantity\": 2}], \"payment_info\": {\"token\": \"test_success_visa\", \"amount\": 100.00}, \"customer_info\": {\"email\": \"test@example.com\", \"name\": \"Test Customer\"}}}'"
  end
  
  private
  
  def task_handler_content
    # Return the content from our examples above
    File.read("#{source_root}/task_handler/order_processing_handler.rb")
  end
  
  def step_handler_content(step_name)
    File.read("#{source_root}/step_handlers/#{step_name}_handler.rb")
  end
  
  def product_model_content
    File.read("#{source_root}/models/product.rb")
  end
  
  def order_model_content
    File.read("#{source_root}/models/order.rb")
  end
  
  def inventory_log_model_content
    <<~RUBY
      class InventoryLog < ApplicationRecord
        validates :changes, presence: true
        validates :reason, presence: true
        
        serialize :changes, Array
        
        scope :for_task, ->(task_id) { where(task_id: task_id) }
        scope :by_reason, ->(reason) { where(reason: reason) }
      end
    RUBY
  end
  
  def email_log_model_content
    <<~RUBY
      class EmailLog < ApplicationRecord
        validates :email_type, presence: true
        validates :recipient, presence: true
        validates :status, presence: true
        
        enum status: {
          pending: 'pending',
          delivered: 'delivered',
          failed: 'failed',
          bounced: 'bounced'
        }
        
        scope :for_order, ->(order_id) { where(order_id: order_id) }
        scope :for_task, ->(task_id) { where(task_id: task_id) }
      end
    RUBY
  end
  
  def controller_content
    File.read("#{source_root}/demo/checkout_controller.rb")
  end
  
  def payment_simulator_content
    File.read("#{source_root}/demo/payment_simulator.rb")
  end
  
  def sample_data_content
    File.read("#{source_root}/demo/sample_data.rb")
  end
  
  def yaml_config_content
    <<~YAML
      ---
      name: ecommerce/process_order
      namespace_name: ecommerce
      version: 1.0.0
      description: "E-commerce order processing workflow with payment and inventory"
      
      schema:
        type: object
        required:
          - cart_items
          - payment_info
          - customer_info
        properties:
          cart_items:
            type: array
            items:
              type: object
              properties:
                product_id:
                  type: integer
                quantity:
                  type: integer
          payment_info:
            type: object
            properties:
              token:
                type: string
              amount:
                type: number
          customer_info:
            type: object
            properties:
              email:
                type: string
              name:
                type: string
      
      step_templates:
        - name: validate_cart
          description: Validate cart items and calculate totals
          handler_class: Ecommerce::StepHandlers::ValidateCartHandler
          retryable: true
          retry_limit: 3
          
        - name: process_payment
          description: Charge payment method
          depends_on_step: validate_cart
          handler_class: Ecommerce::StepHandlers::ProcessPaymentHandler
          retryable: true
          retry_limit: 3
          timeout: 30
          
        - name: update_inventory
          description: Update inventory levels
          depends_on_step: process_payment
          handler_class: Ecommerce::StepHandlers::UpdateInventoryHandler
          retryable: true
          retry_limit: 2
          
        - name: create_order
          description: Create order record
          depends_on_step: update_inventory
          handler_class: Ecommerce::StepHandlers::CreateOrderHandler
          
        - name: send_confirmation
          description: Send order confirmation email
          depends_on_step: create_order
          handler_class: Ecommerce::StepHandlers::SendConfirmationHandler
          retryable: true
          retry_limit: 5
    YAML
  end
end
