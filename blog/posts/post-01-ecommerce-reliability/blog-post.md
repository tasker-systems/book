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

Here's what their original checkout looked like:

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

After their Black Friday nightmare, Sarah's (again, completely imaginary) team discovered Tasker. Here's how they rebuilt their checkout as a reliable, observable workflow:

**First, the YAML configuration that defines the workflow structure:**

```yaml
# config/tasker/tasks/ecommerce/order_processing_handler.yaml
---
name: process_order
namespace_name: ecommerce
version: 1.0.0
task_handler_class: Ecommerce::OrderProcessingHandler

description: "Reliable e-commerce checkout workflow with automatic retry and recovery"

schema:
  type: object
  required: ['cart_items', 'payment_info', 'customer_info']
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
          price:
            type: number
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
    timeout: 30000  # 30 seconds

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
    retry_limit: 5  # Email delivery can be flaky
```

**Then, the handler class that provides runtime behavior:**

```ruby
# app/tasks/ecommerce/order_processing_handler.rb
module Ecommerce
  class OrderProcessingHandler < Tasker::ConfiguredTask
    # Configuration is driven by the YAML file above
    # This class handles runtime behavior and enterprise features

    def establish_step_dependencies_and_defaults(task, steps)
      # Add runtime optimizations based on order context
      if task.context['priority'] == 'express'
        # Express orders get faster timeouts and fewer retries
        payment_step = steps.find { |s| s.name == 'process_payment' }
        payment_step&.update(timeout: 15000, retry_limit: 1)

        email_step = steps.find { |s| s.name == 'send_confirmation' }
        email_step&.update(retry_limit: 2)
      end
    end

    def update_annotations(task, sequence, steps)
      # Track order processing metrics for business intelligence
      payment_step = steps.find { |s| s.name == 'process_payment' }
      if payment_step&.current_state == 'completed'
        payment_results = payment_step.results

        task.annotations.create!(
          annotation_type: 'payment_processed',
          content: {
            payment_id: payment_results['payment_id'],
            amount_charged: payment_results['amount_charged'],
            processing_time_ms: payment_step.duration
          }
        )
      end

      # Track completion metrics
      if task.current_state == 'completed'
        total_duration = steps.sum { |s| s.duration || 0 }
        task.annotations.create!(
          annotation_type: 'checkout_completed',
          content: {
            total_duration_ms: total_duration,
            steps_completed: steps.count,
            customer_email: task.context['customer_info']['email']
          }
        )
      end
    end
  end
end
```

Now each step is isolated, retryable, and has clear dependencies. Let's look at how they implemented the individual step handlers:

```ruby
# app/tasks/ecommerce/step_handlers/validate_cart_handler.rb
module Ecommerce
  module StepHandlers
    class ValidateCartHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        cart_items = task.context['cart_items']

        # Validate each item exists and is available
        validated_items = cart_items.map do |item|
          product = Product.find(item['product_id'])
          raise "Product #{item['product_id']} not found" unless product
          raise "Insufficient stock for #{product.name}" if product.stock < item['quantity']

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
        # if only tax calculation was this easy, but still, go along with it
        tax = subtotal * 0.08  # 8% tax
        # also, we're apparently not charging for shipping, applying coupons, or anything else
        # but we're charging for tax, so that's something
        total = subtotal + tax

        {
          validated_items: validated_items,
          subtotal: subtotal,
          tax: tax,
          total: total
        }
      end
    end
  end
end
```

```ruby
# app/tasks/ecommerce/step_handlers/process_payment_handler.rb
module Ecommerce
  module StepHandlers
    class ProcessPaymentHandler < Tasker::StepHandler::Base
      def process(task, sequence, step)
        payment_info = task.context['payment_info']
        totals = step_results(sequence, 'validate_cart')

        Rails.logger.info "Processing payment", {
          task_id: task.id,
          correlation_id: task.correlation_id,
          amount: totals['total']
        }

        result = PaymentProcessor.charge(
          amount: totals['total'],
          payment_method: payment_info['token']
        )

        unless result.success?
          if result.retryable?
            # Temporary failure - will retry based on step configuration
            Rails.logger.warn "Payment temporarily failed, will retry: #{result.error}"
            raise StandardError, "Payment temporarily failed: #{result.error}"
          else
            # Permanent failure - won't retry
            Rails.logger.error "Payment failed permanently: #{result.error}"
            raise StandardError, "Payment failed: #{result.error}"
          end
        end

        Rails.logger.info "Payment processed successfully", {
          task_id: task.id,
          payment_id: result.id,
          amount_charged: result.amount
        }

        {
          payment_id: result.id,
          amount_charged: result.amount,
          processed_at: Time.current
        }
      end
    end
  end
end
```

## The Magic: What Changed

### 1. **Atomic Steps with Clear Dependencies**

Each step is now atomic and isolated. If inventory update fails, the payment has already succeeded and been recorded. Tasker knows exactly where to restart.

### 2. **Intelligent Retry Logic**

```ruby
# Different retry strategies for different failure types
templates.define(
  name: 'process_payment',
  retryable: true,
  retry_limit: 3,        # Payment processors can be flaky
  timeout: 30.seconds
)

templates.define(
  name: 'send_confirmation',
  retryable: true,
  retry_limit: 5,        # Email delivery often needs more retries
  timeout: 10.seconds
)
```

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

### 4. **Visibility and Debugging**

No more guessing what went wrong:

```ruby
# Get complete execution history
task.workflow_step_sequences.last.workflow_steps.each do |step|
  puts "#{step.name}: #{step.current_state} (#{step.duration}ms)"
  puts "  Result: #{step.results}" if step.current_state == 'completed'
  puts "  Error: #{step.error_message}" if step.current_state == 'failed'
  puts "  Correlation ID: #{step.correlation_id}"
end

# Output:
# validate_cart: completed (45ms)
#   Result: {"total"=>156.32, "validated_items"=>[...]}
#   Correlation ID: req_abc123
# process_payment: completed (1200ms)
#   Result: {"payment_id"=>"pi_1234", "amount_charged"=>156.32}
#   Correlation ID: req_abc123
# update_inventory: failed (30000ms)
#   Error: "Inventory service timeout after 30 seconds"
#   Correlation ID: req_abc123
```

**Enterprise Observability Features:**

```ruby
# Access via REST API for monitoring dashboards
response = HTTParty.get("http://localhost:3000/tasker/tasks/#{task_id}/steps")
steps_data = JSON.parse(response.body)

# OpenTelemetry traces (if configured)
# Automatic tracing spans are created for each step
# View in Jaeger, Zipkin, or your observability platform

# Event-driven monitoring
class CheckoutMonitor < Tasker::EventSubscriber::Base
  subscribe_to 'step.failed', 'task.completed'

  def handle_step_failed(event)
    if event[:namespace] == 'ecommerce' && event[:step_name] == 'process_payment'
      # Alert payment team immediately
      SlackAPI.post_message(
        channel: '#payments-critical',
        text: "Payment failure in checkout: #{event[:error_message]}",
        metadata: { correlation_id: event[:correlation_id] }
      )
    end
  end

  def handle_task_completed(event)
    # Track successful checkout metrics
    Metrics.increment('checkout.completed', {
      namespace: event[:namespace],
      duration_ms: event[:total_duration]
    })
  end
end
```

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
      cart_items: params[:cart_items],
      payment_info: params[:payment_info],
      customer_info: params[:customer_info]
    }
  )

  task_id = Tasker::HandlerFactory.instance.run_task(task_request)
  task = Tasker::Task.find(task_id)

  render json: {
    task_id: task.id,
    status: task.current_state,
    checkout_url: "/orders/#{task.id}/status",
    correlation_id: task.correlation_id
  }
end

# Check status endpoint
def order_status
  task = Tasker::Task.find(params[:task_id])

  case task.current_state
  when 'completed'
    order_step = task.workflow_step_sequences.last.workflow_steps.find_by(name: 'create_order')
    order_id = order_step.results['order_id']
    redirect_to order_path(order_id)
  when 'failed'
    render :checkout_error, locals: {
      error: task.error_summary,
      correlation_id: task.correlation_id
    }
  else
    render :processing, locals: {
      task_id: task.id,
      correlation_id: task.correlation_id
    }
  end
end

# Alternative: Use REST API for status checks (great for JavaScript frontends)
def order_status_api
  # Proxy to Tasker's REST API
  response = HTTParty.get("#{request.base_url}/tasker/tasks/#{params[:task_id]}")
  render json: response.parsed_response
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

## Want to Try This Yourself?

The complete code for this e-commerce checkout workflow is available and can be running in your development environment in under 5 minutes using Tasker's automated demo builder:

```bash
# Interactive setup with full observability stack
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash

# Or specify your preferences for this e-commerce example
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
  --app-name ecommerce-checkout-demo \
  --tasks ecommerce \
  --observability \
  --non-interactive

# Navigate to your new application
cd ecommerce-checkout-demo

# Everything is already configured and ready to run:
# - PostgreSQL database with Tasker tables
# - Redis for background job processing
# - Tasker engine mounted at /tasker
# - Example workflows pre-configured
# - OpenTelemetry tracing (if enabled)

# Start the application
bundle exec rails server

# Test the reliable checkout
open http://localhost:3000

# Monitor workflows via Tasker's REST API
open http://localhost:3000/tasker/tasks

# View handler documentation
open http://localhost:3000/tasker/handlers
```

**What you get out of the box:**
- Complete e-commerce checkout workflow with all step handlers
- Automatic retry logic and error handling
- REST API endpoints for monitoring
- OpenTelemetry integration for tracing (if enabled)
- Example data and test scenarios
- Production-ready patterns with correlation IDs and structured logging

## 📊 Monitoring Your Checkout Performance (New in v1.0.0)

With Tasker's new analytics capabilities, Sarah's team can now monitor their checkout performance in real-time:

```bash
# Get overall system health
curl -H "Authorization: Bearer $API_TOKEN" \
  https://growthcorp.com/tasker/analytics/performance

# Analyze checkout workflow bottlenecks
curl -H "Authorization: Bearer $API_TOKEN" \
  "https://growthcorp.com/tasker/analytics/bottlenecks?namespace=ecommerce&task_name=process_order"
```

**What they discovered:**
- Payment processing step averages 2.8 seconds (95th percentile: 4.2s)
- Inventory updates have a 0.8% retry rate due to timeouts
- System health score: 94.2% (excellent for Black Friday!)

This real-time insight helps them proactively optimize before problems impact customers.

In our next post, we'll explore how to handle even more complex scenarios with parallel execution and event-driven monitoring when we tackle "The Data Pipeline That Kept Everyone Awake."

---

*Have you dealt with similar reliability challenges in your workflows? Share your war stories in the comments below.*
