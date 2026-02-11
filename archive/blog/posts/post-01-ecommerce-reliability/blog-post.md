# When Your E-commerce Checkout Became a House of Cards

*How one imaginary team transformed their fragile Black Friday nightmare into a bulletproof workflow engine*

---

## The 3 AM Wake-Up Call

It's Black Friday, 2023. Sarah, the lead engineer at GrowthCorp, gets the call every e-commerce engineer dreads:

> "Checkout is failing 15% of the time. Credit cards are being charged but orders aren't being created. Customer support has 200 tickets and counting. We're losing $50K per hour."

Sound familiar? I really hope not, for your sake. But it probably does, because if it didn't, you might not be reading this.

Sarah's team had built what looked like a solid checkout flow. It worked perfectly in staging. The code was clean, the tests passed, and the load tests showed it could handle 10x their normal traffic.

But production is different. Payment processors have hiccups. Inventory services timeout. Email delivery fails. And when any piece fails, the entire checkout becomes a house of cards.

## The Fragile Foundation

Here's what their original checkout looked like - a typical monolithic service that tries to do everything in one transaction:

```ruby
class CheckoutService
  def process_order(cart_items, payment_info, customer_info)
    # Step 1: Validate the cart
    validated_items = validate_cart_items(cart_items)
    raise "Invalid cart" if validated_items.empty?

    # Step 2: Calculate totals
    totals = calculate_order_totals(validated_items)

    # Step 3: Process payment
    payment_result = PaymentProcessor.charge(
      amount: totals[:total],
      payment_method: payment_info
    )
    raise "Payment failed" unless payment_result.success?

    # Step 4: Update inventory
    update_inventory_levels(validated_items)

    # Step 5: Create the order
    order = Order.create!(
      items: validated_items,
      total: totals[:total],
      payment_id: payment_result.id,
      customer: customer_info
    )

    # Step 6: Send confirmation
    OrderMailer.confirmation_email(order).deliver_now

    order
  rescue => e
    # What do we do here? Payment might be charged...
    logger.error "Checkout failed: #{e.message}"
    raise
  end
end
```

**What could go wrong?** Everything.

- **Payment succeeds, inventory update fails**: Customer charged, no order created
- **Order created, email fails**: Customer doesn't know about their order
- **Inventory updated, order creation fails**: Products locked, no record of purchase
- **Any failure requires manual investigation**: No visibility into which step failed

During their Black Friday meltdown, Sarah's team spent 6 hours manually reconciling payments, inventory, and orders. Every engineer on the team was debugging production instead of sleeping.

## The Reliable Alternative

After their Black Friday nightmare, Sarah's (again, completely imaginary) team discovered Tasker. Here's how they rebuilt their checkout as a reliable, observable workflow.

### Complete Working Examples

All the code examples in this post are **tested and validated** in the Tasker engine repository. You can see the complete, working implementation here:

**📁 [E-commerce Reliability Examples](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_01_ecommerce_reliability)**

This includes:
- **[YAML Configuration](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/config/order_processing_handler.yaml)** - Workflow structure and retry policies
- **[Task Handler](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/task_handler/order_processing_handler.rb)** - Runtime behavior and enterprise features
- **[Step Handlers](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_01_ecommerce_reliability/step_handlers)** - Individual workflow steps
- **[Models](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_01_ecommerce_reliability/models)** - Order and Product models
- **[Demo Scripts](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_01_ecommerce_reliability/demo)** - Interactive examples you can run

### Key Configuration Highlights

The **[YAML configuration](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/config/order_processing_handler.yaml)** separates workflow structure from business logic:

```yaml
# Excerpt from the tested configuration
step_templates:
  - name: validate_cart
    description: Validate cart items and calculate totals
    handler_class: Ecommerce::StepHandlers::ValidateCartHandler
    default_retryable: true
    default_retry_limit: 3

  - name: process_payment
    description: Charge payment method
    depends_on_step: validate_cart
    handler_class: Ecommerce::StepHandlers::ProcessPaymentHandler
    default_retryable: true
    default_retry_limit: 3
    handler_config:
      timeout_seconds: 30
```

### Business Logic in Step Handlers

Each step is implemented as a focused, testable class. For example, the **[ValidateCartHandler](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/step_handlers/validate_cart_handler.rb)** handles cart validation and pricing:

```ruby
# See the complete implementation with error handling and validation
module Ecommerce
  module StepHandlers
    class ValidateCartHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        cart_items = task.context['cart_items']

        # Validate each item exists and is available
        validated_items = cart_items.map do |item|
          product = Product.find_by(id: item['product_id'])

          unless product
            raise StandardError, "Product #{item['product_id']} not found"
          end

          unless product.active?
            raise StandardError, "Product #{product.name} is no longer available"
          end

          if product.stock < item['quantity']
            raise StandardError, "Insufficient stock for #{product.name}"
          end

          {
            product_id: product.id,
            name: product.name,
            price: product.price,
            quantity: item['quantity'],
            line_total: product.price * item['quantity']
          }
        end

        # Calculate totals
        subtotal = validated_items.sum { |item| item[:line_total] }
        tax = (subtotal * 0.08).round(2)  # 8% tax
        shipping = calculate_shipping(validated_items)
        total = subtotal + tax + shipping

        {
          validated_items: validated_items,
          subtotal: subtotal,
          tax: tax,
          shipping: shipping,
          total: total,
          validated_at: Time.current.iso8601
        }
      end

      private

      def calculate_shipping(items)
        total_weight = items.sum { |item| item[:quantity] * 0.5 }
        case total_weight
        when 0..2 then 5.99
        when 2..10 then 9.99
        else 14.99
        end
      end
    end
  end
end
```

Now each step is isolated, retryable, and has clear dependencies. You can see the complete implementation of all step handlers in the GitHub repository:

- **[ValidateCartHandler](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/step_handlers/validate_cart_handler.rb)** - Cart validation and pricing calculation
- **[ProcessPaymentHandler](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/step_handlers/process_payment_handler.rb)** - Payment processing with intelligent retry logic
- **[UpdateInventoryHandler](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/step_handlers/update_inventory_handler.rb)** - Inventory management
- **[CreateOrderHandler](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/step_handlers/create_order_handler.rb)** - Order record creation
- **[SendConfirmationHandler](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/step_handlers/send_confirmation_handler.rb)** - Email delivery with retry logic

Each handler includes:
- **Error handling** for both retryable and permanent failures
- **Structured logging** with correlation IDs for tracing
- **Input validation** and **result formatting**
- **Integration with external services** (payment processors, inventory systems)

## The Magic: What Changed

### 1. **Atomic Steps with Clear Dependencies**

Each step is now atomic and isolated. If inventory update fails, the payment has already succeeded and been recorded. Tasker knows exactly where to restart.

### 2. **Intelligent Retry Logic**

Different retry strategies for different failure types:
- Payment processing: 3 retries with 30-second timeout
- Email delivery: 5 retries (email services are often flaky)
- Inventory updates: 2 retries with shorter timeout

See the complete retry configuration in the **[YAML file](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/config/order_processing_handler.yaml)**.

### 3. **Built-in State Management**

Tasker tracks the state of every step. If something fails, you can see exactly where:

```ruby
# Check task status
task = Tasker::Task.find(task_id)
puts task.current_state  # 'failed'

# See which step failed
failed_step = task.workflow_step_sequences.last.workflow_steps.where(current_state: 'failed').first
puts failed_step.name           # 'update_inventory'
puts failed_step.error_message  # 'Inventory service timeout'

# Retry the entire workflow (Tasker will skip completed steps)
task.retry!

# Or access via REST API
require 'net/http'
response = Net::HTTP.get_response(URI("http://localhost:3000/tasker/tasks/#{task_id}"))
task_data = JSON.parse(response.body)
puts "Task Status: #{task_data['current_state']}"
puts "Failed Step: #{task_data['workflow_steps'].find { |s| s['current_state'] == 'failed' }&.dig('name')}"
```

### 4. **REST API for Monitoring**

Complete visibility through Tasker's REST API:

```bash
# Get task status
curl http://localhost:3000/tasker/tasks/{task_id}

# Get step-by-step execution details
curl http://localhost:3000/tasker/tasks/{task_id}/steps

# Monitor system health
curl http://localhost:3000/tasker/analytics/performance
```

### 5. **Event-Driven Monitoring**

The **[event subscriber examples](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_01_ecommerce_reliability/event_subscribers)** show how to implement real-time monitoring and alerting.

## How to Execute the Workflow

Using this new reliable workflow is simple:

```ruby
# In your controller
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
    task_id: task.task_id,
    status: task.status,
    checkout_url: order_status_path(task_id: task.task_id)
  }
rescue Tasker::ValidationError => e
  render json: {
    success: false,
    error: 'Invalid checkout data',
    details: e.message
  }, status: :unprocessable_entity
end

# Check status endpoint
def order_status
  task = Tasker::Task.find(params[:task_id])

  case task.status
  when 'complete'
    order_step = task.get_step_by_name('create_order')
    order_id = order_step.results['order_id']

    render json: {
      status: 'completed',
      order_id: order_id,
      order_number: order_step.results['order_number'],
      total_amount: order_step.results['total_amount'],
      redirect_url: order_path(order_id)
    }
  when 'error'
    failed_step = task.workflow_steps.where("status = 'error'").first

    render json: {
      status: 'failed',
      failed_step: failed_step&.name,
      retry_url: retry_checkout_path(task_id: task.task_id)
    }
  when 'processing'
    summary = task.workflow_summary

    render json: {
      status: 'processing',
      current_step: task.workflow_steps.where("status = 'processing'").first&.name,
      progress: {
        completed: summary[:completed],
        total: summary[:total_steps],
        percentage: summary[:completion_percentage]
      }
    }
  end
end
```

## The Results (Again, Imaginary, But Directly Inspired by Real-World Experience)

**Before Tasker:**
- 15% checkout failure rate during peak traffic
- 6-hour manual reconciliation after failures
- No visibility into failure points
- Customer support overwhelmed with "where's my order?" tickets

**After Tasker:**
- 0.2% checkout failure rate (only non-retryable payment failures)
- Automatic recovery for 98% of transient failures
- Complete visibility into every step
- Failed steps retry automatically with exponential backoff

Sarah's team went from being woken up every Black Friday to sleeping soundly while their workflows handled millions of orders reliably.

## Key Takeaways

1. **Break monolithic processes into atomic steps** - Each step should do one thing well and be independently retryable

2. **Define clear dependencies** - Tasker ensures steps execute in the right order and only when their dependencies succeed

3. **Embrace failure as normal** - Design for failure with appropriate retry strategies for different types of errors

4. **Make everything observable** - You can't fix what you can't see. Tasker gives you complete visibility into workflow execution

5. **Think in workflows, not procedures** - Workflows can pause, retry, and resume. Procedures just fail.

## Try It Yourself

The **[complete working examples](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_01_ecommerce_reliability)** include:

### 🏃‍♂️ **[Quick Setup Scripts](https://github.com/tasker-systems/tasker/tree/main/spec/blog/post_01_ecommerce_reliability/setup-scripts)**
```bash
# Clone and run the examples
git clone https://github.com/tasker-systems/tasker.git
cd tasker/spec/blog/post_01_ecommerce_reliability
./setup-scripts/setup.sh

# Start the demo
./setup-scripts/demo.sh
```

### 🧪 **[Interactive Demo](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/demo/checkout_controller.rb)**
- Simulates real checkout scenarios
- Demonstrates failure handling and recovery
- Shows monitoring and observability features

### 📊 **[Testing Suite](https://github.com/tasker-systems/tasker/blob/main/spec/blog/post_01_ecommerce_reliability/TESTING.md)**
- Complete RSpec tests for all components
- Performance benchmarks
- Failure scenario testing

## 📊 Monitoring Your Checkout Performance

With Tasker's analytics capabilities, you can monitor checkout performance in real-time:

```bash
# Get overall system health
curl -H "Authorization: Bearer $API_TOKEN" \
  https://your-app.com/tasker/analytics/performance

# Analyze checkout workflow bottlenecks
curl -H "Authorization: Bearer $API_TOKEN" \
  "https://your-app.com/tasker/analytics/bottlenecks?namespace=ecommerce&task_name=process_order"
```

## What's Next?

In our next post, we'll explore how to handle even more complex scenarios with parallel execution and event-driven monitoring when we tackle **"The Data Pipeline That Kept Everyone Awake."**

All examples in this series are **tested, validated, and ready to run** in the [Tasker engine repository](https://github.com/tasker-systems/tasker/tree/main/spec/blog).

---

*Have you dealt with similar reliability challenges in your workflows? Share your war stories in the comments below.*
