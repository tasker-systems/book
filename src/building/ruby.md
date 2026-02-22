# Building with Ruby

This guide covers building Tasker step handlers with Ruby using the `tasker-rb` gem
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

This creates a DSL-style handler with typed inputs that delegates to a service method.

## Writing a Handler (DSL)

Every handler follows the three-layer pattern: **type definition**, **handler declaration**, **service delegation**.

```ruby
# app/services/types.rb — the contract
module Types
  module Ecommerce
    class OrderInput < Types::InputStruct
      attribute :cart_items, Types::Array.optional
      attribute :customer_email, Types::String.optional
      attribute :payment_info, Types::Hash.optional
      attribute :shipping_address, Types::Hash.optional
    end
  end
end

# app/handlers/ecommerce/step_handlers/validate_cart_handler.rb — the handler
module Ecommerce
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    ValidateCartHandler = step_handler(
      'Ecommerce::StepHandlers::ValidateCartHandler',
      inputs: Types::Ecommerce::OrderInput
    ) do |inputs:, context:|
      Ecommerce::Service.validate_cart_items(
        cart_items: inputs.cart_items,
        customer_email: inputs.customer_email,
      )
    end
  end
end
```

The `step_handler` method registers a handler and takes a block. The `inputs:` keyword argument receives a `Dry::Struct` instance with typed, optional attributes. The block body is a single service call.

## Type System

Ruby handlers use **`Dry::Struct`** for both input and result types.

**Input types** extend `Types::InputStruct` — a base class where all attributes are optional and omittable, so missing keys don't raise:

```ruby
module Types
  module Ecommerce
    class OrderInput < Types::InputStruct
      attribute :cart_items, Types::Array.optional
      attribute :customer_email, Types::String.optional
      attribute :payment_info, Types::Hash.optional
      attribute :shipping_address, Types::Hash.optional
    end
  end
end
```

**Result types** extend `Types::ResultStruct` — similar to `InputStruct` but describing what a handler returns (used by downstream `depends_on`):

```ruby
module Types
  module Ecommerce
    class ValidateCartResult < Types::ResultStruct
      attribute :validated_items, Types::Array
      attribute :item_count, Types::Integer
      attribute :subtotal, Types::Float
      attribute :tax, Types::Float
      attribute :total, Types::Float
    end
  end
end
```

Both `InputStruct` and `ResultStruct` support string and symbol key access (e.g., `result['user_id']` and `result[:user_id]`) and nested access via `dig`.

## Accessing Task Context

The `inputs:` config extracts the full task context into a typed `Dry::Struct` instance. Fields are matched by name from the submitted JSON:

```ruby
ValidateCartHandler = step_handler(
  'Ecommerce::StepHandlers::ValidateCartHandler',
  inputs: Types::Ecommerce::OrderInput
) do |inputs:, context:|
  # inputs.cart_items, inputs.customer_email, etc. are typed attributes
  Ecommerce::Service.validate_cart_items(cart_items: inputs.cart_items)
end
```

The `context:` keyword provides execution metadata (task UUID, step UUID, step config) but most handlers don't need it directly.

## Working with Dependencies

The `depends_on:` config injects typed results from upstream steps. Each entry maps a keyword argument name to a `['step_name', ResultModel]` pair:

```ruby
ProcessPaymentHandler = step_handler(
  'Ecommerce::StepHandlers::ProcessPaymentHandler',
  depends_on: { cart_total: ['validate_cart', Types::Ecommerce::ValidateCartResult] },
  inputs: Types::Ecommerce::OrderInput
) do |cart_total:, inputs:, context:|
  Ecommerce::Service.process_payment(
    payment_info: inputs.payment_info,
    total: cart_total&.total,
  )
end
```

Handlers can reference **any ancestor step** in the DAG — not just direct predecessors. Here's a convergence handler that accesses three upstream steps:

```ruby
CreateOrderHandler = step_handler(
  'Ecommerce::StepHandlers::CreateOrderHandler',
  depends_on: {
    cart_validation: ['validate_cart', Types::Ecommerce::ValidateCartResult],
    payment_result: ['process_payment', Types::Ecommerce::ProcessPaymentResult],
    inventory_result: ['update_inventory', Types::Ecommerce::UpdateInventoryResult],
  },
  inputs: Types::Ecommerce::OrderInput
) do |cart_validation:, payment_result:, inventory_result:, inputs:, context:|
  Ecommerce::Service.create_order(
    cart_validation: cart_validation,
    payment_result: payment_result,
    inventory_result: inventory_result,
    customer_email: inputs.customer_email,
    shipping_address: inputs.shipping_address,
  )
end
```

## Multi-Step Example: Data Pipeline

The data pipeline workflow demonstrates a parallel DAG — three independent extract branches, each feeding its own transform, converging at aggregation:

```text
extract_sales    extract_inventory    extract_customers
     │                  │                    │
     ▼                  ▼                    ▼
transform_sales  transform_inventory  transform_customers
     │                  │                    │
     └──────────────────┼────────────────────┘
                        ▼
               aggregate_metrics
                        │
                        ▼
              generate_insights
```

Ruby handlers follow the same concise pattern:

```ruby
module DataPipeline
  module StepHandlers
    extend TaskerCore::StepHandler::Functional

    # Extract — no dependencies, runs in parallel
    ExtractSalesDataHandler = step_handler(
      'DataPipeline::StepHandlers::ExtractSalesDataHandler',
      inputs: Types::DataPipeline::PipelineInput
    ) do |inputs:, context:|
      DataPipeline::Service.extract_sales_data(
        source: inputs.source,
        date_range_start: inputs.date_range_start,
      )
    end

    # Transform — depends on one extract branch
    TransformSalesHandler = step_handler(
      'DataPipeline::StepHandlers::TransformSalesHandler',
      depends_on: { sales_data: ['extract_sales_data', Types::DataPipeline::ExtractSalesResult] }
    ) do |sales_data:, context:|
      DataPipeline::Service.transform_sales(sales_data: sales_data)
    end

    # Aggregate — converges three transform branches
    AggregateMetricsHandler = step_handler(
      'DataPipeline::StepHandlers::AggregateMetricsHandler',
      depends_on: {
        sales: ['transform_sales', Types::DataPipeline::TransformSalesResult],
        inventory: ['transform_inventory', Types::DataPipeline::TransformInventoryResult],
        customers: ['transform_customers', Types::DataPipeline::TransformCustomersResult],
      }
    ) do |sales:, inventory:, customers:, context:|
      DataPipeline::Service.aggregate_metrics(
        sales: sales, inventory: inventory, customers: customers,
      )
    end
  end
end
```

## Error Handling

Raise typed exceptions to control retry behavior:

```ruby
# Permanent error — will NOT be retried
raise TaskerCore::Errors::PermanentError.new(
  'Payment declined: insufficient funds',
  error_code: 'PAYMENT_DECLINED'
)

# Retryable error — will be retried per the step's retry config
raise TaskerCore::Errors::RetryableError.new(
  'Payment gateway temporarily unavailable'
)
```

Error codes (like `PAYMENT_DECLINED`, `EMPTY_CART`) are included in the step result for observability and debugging.

## Testing

DSL handlers are constants holding callable blocks — test by invoking the service functions directly or by using RSpec mocks:

```ruby
RSpec.describe 'Ecommerce::StepHandlers::ValidateCartHandler' do
  let(:inputs) do
    Types::Ecommerce::OrderInput.new(
      cart_items: [{ 'sku' => 'SKU-001', 'name' => 'Widget', 'quantity' => 2, 'unit_price' => 29.99 }],
      customer_email: 'test@example.com'
    )
  end

  it 'delegates to the service' do
    expect(Ecommerce::Service).to receive(:validate_cart_items)
      .with(cart_items: inputs.cart_items, customer_email: inputs.customer_email)
      .and_return({ validated_items: [], total: 64.79 })

    context = instance_double(TaskerCore::Types::StepContext)
    result = Ecommerce::StepHandlers::ValidateCartHandler.call(inputs: inputs, context: context)

    expect(result[:total]).to eq(64.79)
  end
end
```

For handlers with dependencies, construct result models directly:

```ruby
let(:cart) { Types::Ecommerce::ValidateCartResult.new(total: 64.79, validated_items: []) }
let(:payment) { Types::Ecommerce::ProcessPaymentResult.new(payment_id: 'pay_abc') }
let(:inventory) { Types::Ecommerce::UpdateInventoryResult.new(inventory_log_id: 'log_123') }
let(:inputs) { Types::Ecommerce::OrderInput.new(customer_email: 'test@example.com') }

it 'creates order from upstream data' do
  expect(Ecommerce::Service).to receive(:create_order)
    .and_return({ order_id: 'ORD-001' })

  context = instance_double(TaskerCore::Types::StepContext)
  result = Ecommerce::StepHandlers::CreateOrderHandler.call(
    cart_validation: cart, payment_result: payment,
    inventory_result: inventory, inputs: inputs, context: context,
  )

  expect(result[:order_id]).to eq('ORD-001')
end
```

Because handlers delegate to service methods, you can also test the services directly without any Tasker infrastructure.

## Handler Variants

### API Handler

Adds HTTP client methods with built-in error classification. Uses `TaskerCore::StepHandler::Mixins::API` with the class-based pattern. See [Class-Based Handlers — API Handler](../reference/class-based-handlers.md#api-handler).

### Decision Handler

Adds workflow routing with `decision_success()` for activating downstream step sets. Uses `TaskerCore::StepHandler::Mixins::Decision` with the class-based pattern. See [Conditional Workflows](../guides/conditional-workflows.md).

### Batchable Handler

Adds batch processing with Analyzer/Worker pattern using `TaskerCore::StepHandler::Mixins::Batchable`. See [Class-Based Handlers — Batchable Handler](../reference/class-based-handlers.md#batchable-handler) and [Batch Processing](../guides/batch-processing.md).

## Class-Based Alternative

If you prefer class inheritance, all handler types support a class-based pattern where you inherit from `TaskerCore::StepHandler::Base` and implement `call(context)`. See [Class-Based Handlers](../reference/class-based-handlers.md) for the full reference.

## Next Steps

- [Your First Workflow](first-workflow.md) — Build a multi-step DAG end-to-end
- [Architecture](../architecture/index.md) — System design details
- [Rails example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/rails-app) — Complete working implementation
