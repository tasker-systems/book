# Building with Ruby

This guide covers building Tasker step handlers with Ruby using the `tasker_core` gem
in a Rails application.

## Quick Start

Add the gem to your Gemfile:

```ruby
gem 'tasker-rb'
```

Generate a step handler with `tasker-ctl`:

```bash
tasker-ctl template generate step_handler \
  --language ruby \
  --param name=ValidateCart \
  --param module_name=Ecommerce
```

This creates a handler class that extends `TaskerCore::StepHandler::Base` with the
standard `call(context)` method.

## Writing a Step Handler

Every Ruby handler inherits from `TaskerCore::StepHandler::Base` and implements `call`:

```ruby
module Ecommerce
  module StepHandlers
    class ValidateCartHandler < TaskerCore::StepHandler::Base
      def call(context)
        cart_items = context.get_input('cart_items')

        raise TaskerCore::Errors::PermanentError.new(
          'Cart is empty',
          error_code: 'EMPTY_CART'
        ) if cart_items.nil? || cart_items.empty?

        # Validate items, calculate totals...
        subtotal = 0.0
        validated_items = cart_items.map do |item|
          line_total = (item['quantity'].to_i * item['unit_price'].to_f).round(2)
          subtotal += line_total
          { sku: item['sku'], name: item['name'], quantity: item['quantity'].to_i,
            unit_price: item['unit_price'].to_f, line_total: line_total }
        end

        tax = (subtotal * 0.08).round(2)
        total = (subtotal + tax).round(2)

        TaskerCore::Types::StepHandlerCallResult.success(
          result: {
            validated_items: validated_items,
            subtotal: subtotal,
            tax: tax,
            total: total
          },
          metadata: {
            handler: self.class.name,
            items_validated: validated_items.size
          }
        )
      end
    end
  end
end
```

The handler receives a `StepContext` and returns a `StepHandlerCallResult` — either
`success` with a result hash and optional metadata, or an error via exceptions.

## Accessing Task Context

Use `get_input()` to read values from the task context (TAS-137 cross-language standard):

```ruby
# Read a top-level field from the task context
cart_items = context.get_input('cart_items')
customer_email = context.get_input('customer_email')

# Read nested data (returns the full object)
payment_info = context.get_input('payment_info')
token = payment_info&.dig(:token)
```

## Accessing Dependency Results

Use `get_dependency_result()` to read results from upstream steps. The return value
is auto-unwrapped — you get the result hash directly:

```ruby
# Get the full result from an upstream step
cart_validation = context.get_dependency_result('validate_cart')
total = cart_validation[:total]

# Extract a single nested field from a dependency result
total = context.get_dependency_field('validate_cart', 'total')

# Combine data from multiple upstream steps
payment_result = context.get_dependency_result('process_payment')
inventory_result = context.get_dependency_result('update_inventory')
```

## Error Handling

Use typed exceptions to control retry behavior:

```ruby
# Permanent error — will NOT be retried (validation failures, bad data)
raise TaskerCore::Errors::PermanentError.new(
  'Payment declined: insufficient funds',
  error_code: 'PAYMENT_DECLINED'
)

# Retryable error — will be retried per the step's retry config
raise TaskerCore::Errors::RetryableError.new(
  'Payment gateway temporarily unavailable'
)
```

Error codes (like `PAYMENT_DECLINED`, `EMPTY_CART`, `MISSING_TOKEN`) are included in
the step result for observability and debugging.

## Task Template Configuration

Generate a task template with `tasker-ctl`:

```bash
tasker-ctl template generate task_template \
  --language ruby \
  --param name=EcommerceOrderProcessing \
  --param namespace=ecommerce \
  --param handler_callable=Ecommerce::OrderProcessingHandler
```

This generates a YAML file defining the workflow. Here is a multi-step example from
the ecommerce example app:

```yaml
name: ecommerce_order_processing
namespace_name: ecommerce_rb
version: 1.0.0
description: "Complete e-commerce order processing workflow"
metadata:
  author: Rails Example App
  tags:
    - namespace:ecommerce
    - pattern:order_processing
    - language:ruby
task_handler:
  callable: Ecommerce::OrderProcessingHandler
  initialization:
    input_validation:
      required_fields:
        - cart_items
        - customer_email
system_dependencies:
  primary: default
  secondary: []
input_schema:
  type: object
  required:
    - cart_items
    - customer_email
  properties:
    cart_items:
      type: array
      items:
        type: object
        required: [sku, name, quantity, unit_price]
    customer_email:
      type: string
      format: email
steps:
  - name: validate_cart
    description: "Validate cart items, calculate totals"
    handler:
      callable: Ecommerce::StepHandlers::ValidateCartHandler
    dependencies: []
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: process_payment
    description: "Process customer payment"
    handler:
      callable: Ecommerce::StepHandlers::ProcessPaymentHandler
    dependencies:
      - validate_cart
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: update_inventory
    description: "Reserve inventory for order items"
    handler:
      callable: Ecommerce::StepHandlers::UpdateInventoryHandler
    dependencies:
      - process_payment
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: create_order
    description: "Create order record"
    handler:
      callable: Ecommerce::StepHandlers::CreateOrderHandler
    dependencies:
      - update_inventory
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000

  - name: send_confirmation
    description: "Send order confirmation email"
    handler:
      callable: Ecommerce::StepHandlers::SendConfirmationHandler
    dependencies:
      - create_order
    retry:
      retryable: true
      max_attempts: 2
      backoff: exponential
      backoff_base_ms: 100
      max_backoff_ms: 5000
```

Key fields:

- **`metadata`** — Tags, authorship, and documentation links
- **`task_handler`** — The top-level handler class and initialization config
- **`system_dependencies`** — External service connections the workflow requires
- **`input_schema`** — JSON Schema validating task input before execution
- **`steps[].handler.callable`** — Fully qualified Ruby class name (e.g., `Ecommerce::StepHandlers::ValidateCartHandler`)
- **`steps[].dependencies`** — DAG edges defining execution order
- **`steps[].retry`** — Per-step retry policy with backoff

## Handler Variants

### API Handler (`step_handler_api`)

```bash
tasker-ctl template generate step_handler_api \
  --language ruby \
  --param name=FetchUser \
  --param module_name=MyApp \
  --param base_url=https://api.example.com
```

Generates a handler that includes `TaskerCore::StepHandler::Mixins::API`, providing
`get`, `post`, `put`, `delete` HTTP methods with automatic error classification.

### Decision Handler (`step_handler_decision`)

```bash
tasker-ctl template generate step_handler_decision \
  --language ruby \
  --param name=RouteOrder \
  --param module_name=MyApp
```

Generates a handler that includes `TaskerCore::StepHandler::Mixins::Decision`, providing
`decision_success()` for routing workflows to different downstream step sets based on
runtime conditions.

### Batchable Handler (`step_handler_batchable`)

```bash
tasker-ctl template generate step_handler_batchable \
  --language ruby \
  --param name=ProcessRecords \
  --param module_name=MyApp
```

Generates an Analyzer/Worker pattern handler using `TaskerCore::StepHandler::Mixins::Batchable`.
The analyzer step divides work into cursor ranges, and worker steps process batches in parallel.

## Testing

The template generates an RSpec test file alongside the handler:

```ruby
RSpec.describe Ecommerce::StepHandlers::ValidateCartHandler do
  subject(:handler) { described_class.new }

  describe '#call' do
    let(:context) do
      ctx = instance_double(TaskerCore::Types::StepContext,
        task_uuid: SecureRandom.uuid,
        step_uuid: SecureRandom.uuid,
        step_config: {}
      )
      allow(ctx).to receive(:get_input).and_return(nil)
      allow(ctx).to receive(:get_input).with('cart_items').and_return([
        { 'sku' => 'SKU-001', 'name' => 'Widget', 'quantity' => 2, 'unit_price' => 29.99 }
      ])
      allow(ctx).to receive(:get_input).with('customer_email').and_return('test@example.com')
      ctx
    end

    it 'validates cart and returns totals' do
      result = handler.call(context)

      expect(result).to be_a(TaskerCore::Types::StepHandlerCallResult::Success)
      expect(result.result[:total]).to be > 0
    end
  end
end
```

Test handlers that use dependency results by stubbing `get_dependency_result`:

```ruby
let(:context_with_deps) do
  ctx = instance_double(TaskerCore::Types::StepContext)
  allow(ctx).to receive(:get_input).with('customer_email').and_return('test@example.com')
  allow(ctx).to receive(:get_dependency_result).with('validate_cart').and_return({
    total: 64.79, validated_items: [{ sku: 'SKU-001', quantity: 2 }]
  })
  allow(ctx).to receive(:get_dependency_result).with('process_payment').and_return({
    payment_id: 'pay_abc123', transaction_id: 'txn_xyz'
  })
  ctx
end
```

## Next Steps

- See the [Quick Start Guide](../guides/quick-start.md) for running the full workflow end-to-end
- See [Architecture](../architecture/index.md) for system design details
- Browse the [Rails example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app) for complete handler implementations
