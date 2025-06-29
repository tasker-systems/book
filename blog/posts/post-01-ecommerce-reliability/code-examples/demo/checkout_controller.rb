# Demo controller showing how to use the e-commerce workflow
class CheckoutController < ApplicationController
  before_action :authenticate_user!, except: [:demo_page]

  # Demo page showing the checkout flow
  def demo_page
    @products = Product.active.in_stock
    @sample_cart = [
      { product_id: 1, quantity: 2 },
      { product_id: 3, quantity: 1 }
    ]
  end

  # Create a new order using the Tasker workflow
  def create_order
    task_request = Tasker::Types::TaskRequest.new(
      name: 'process_order',
      namespace: 'ecommerce',
      version: '1.0.0',
      context: {
        cart_items: checkout_params[:cart_items],
        payment_info: checkout_params[:payment_info],
        customer_info: checkout_params[:customer_info]
      }
    )

    # Execute the workflow asynchronously
    task_id = Tasker::HandlerFactory.instance.run_task(task_request)
    task = Tasker::Task.find(task_id)

    render json: {
      success: true,
      task_id: task.id,
      status: task.current_state,
      checkout_url: order_status_path(task_id: task.id),
      correlation_id: task.correlation_id
    }
  rescue Tasker::ValidationError => e
    render json: {
      success: false,
      error: 'Invalid checkout data',
      details: e.message
    }, status: :unprocessable_entity
  rescue StandardError => e
    render json: {
      success: false,
      error: 'Checkout failed',
      details: e.message
    }, status: :internal_server_error
  end

    # Check the status of an order workflow
  def order_status
    task = Tasker::Task.find(params[:task_id])

    case task.current_state
    when 'completed'
      order_step = task.workflow_step_sequences.last.workflow_steps.find_by(name: 'create_order')
      order_id = order_step.results['order_id']

      render json: {
        status: 'completed',
        order_id: order_id,
        order_number: order_step.results['order_number'],
        total_amount: order_step.results['total_amount'],
        redirect_url: order_path(order_id),
        correlation_id: task.correlation_id
      }
    when 'failed'
      failed_step = task.workflow_step_sequences.last.workflow_steps.where(current_state: 'failed').first

      render json: {
        status: 'failed',
        error: task.error_summary,
        failed_step: failed_step&.name,
        step_error: failed_step&.error_message,
        retry_url: retry_checkout_path(task_id: task.id),
        correlation_id: task.correlation_id
      }
    when 'running'
      current_step = task.workflow_step_sequences.last.workflow_steps.where(current_state: 'running').first
      completed_steps = task.workflow_step_sequences.last.workflow_steps.where(current_state: 'completed').count
      total_steps = task.workflow_step_sequences.last.workflow_steps.count

      render json: {
        status: 'processing',
        current_step: current_step&.name,
        progress: {
          completed: completed_steps,
          total: total_steps,
          percentage: (completed_steps.to_f / total_steps * 100).round
        },
        correlation_id: task.correlation_id
      }
    else
      render json: {
        status: task.current_state,
        message: "Order is #{task.current_state}",
        correlation_id: task.correlation_id
      }
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: 'Order not found'
    }, status: :not_found
  end

  # Retry a failed checkout workflow
  def retry_checkout
    task = Tasker::Task.find(params[:task_id])

        if task.current_state == 'failed'
      task.retry!
      render json: {
        success: true,
        message: 'Checkout retry initiated',
        status: task.current_state,
        correlation_id: task.correlation_id
      }
    else
      render json: {
        success: false,
        error: "Cannot retry task in #{task.current_state} status",
        correlation_id: task.correlation_id
      }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: 'Order not found'
    }, status: :not_found
  end

    # Show detailed workflow execution for debugging
  def workflow_details
    task = Tasker::Task.find(params[:task_id])

    steps_detail = task.workflow_step_sequences.last.workflow_steps.map do |step|
      {
        name: step.name,
        status: step.current_state,
        duration_ms: step.duration,
        result: step.results,
        error: step.error_message,
        retry_count: step.retry_count,
        started_at: step.started_at,
        completed_at: step.completed_at,
        correlation_id: step.correlation_id
      }
    end

    render json: {
      task_id: task.id,
      status: task.current_state,
      started_at: task.started_at,
      completed_at: task.completed_at,
      total_duration_ms: task.duration,
      correlation_id: task.correlation_id,
      steps: steps_detail,
      annotations: task.annotations
    }
  rescue ActiveRecord::RecordNotFound
    render json: {
      error: 'Order not found'
    }, status: :not_found
  end

  private

  def checkout_params
    params.require(:checkout).permit(
      cart_items: [:product_id, :quantity, :price],
      payment_info: [:token, :amount, :payment_method],
      customer_info: [:email, :name, :phone]
    )
  end
end
