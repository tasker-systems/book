# Building with Python

This guide covers building Tasker step handlers with Python using the `tasker_core`
package in a FastAPI application.

## Quick Start

Install the package:

```bash
pip install tasker-py
# Or with uv (recommended)
uv add tasker-py
```

Generate a step handler with `tasker-ctl`:

```bash
tasker-ctl template generate step_handler \
  --language python \
  --param name=ValidateCart \
  --param module_name=handlers.ecommerce
```

This creates a DSL-style handler with typed inputs that delegates to a service function.

## Writing a Handler (DSL)

Every handler follows the three-layer pattern: **type definition**, **handler declaration**, **service delegation**.

```python
# app/services/types.py — the contract
from pydantic import BaseModel
from typing import Any

class EcommerceOrderInput(BaseModel):
    items: list[dict[str, Any]] | None = None
    cart_items: list[dict[str, Any]] | None = None
    customer_email: str | None = None
    payment_token: str | None = None

    @property
    def resolved_items(self) -> list[dict[str, Any]]:
        """Accept either field name from the task context."""
        return self.items or self.cart_items or []

# app/handlers/ecommerce.py — the handler
from tasker_core.step_handler.functional import inputs, step_handler
from app.services.types import EcommerceOrderInput
from app.services import ecommerce as svc

@step_handler("validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context: StepContext):
    return svc.validate_cart_items(inputs.resolved_items)
```

The `@step_handler` decorator registers this function as the handler for the `validate_cart` step. The `@inputs` decorator tells Tasker to extract the task context into a Pydantic model. The function body is a single service call.

## Type System

Python handlers use **Pydantic `BaseModel`** for both input and result types. The DSL deserializes JSON into these models automatically.

**Input types** receive the task context:

```python
class EcommerceOrderInput(BaseModel):
    items: list[dict[str, Any]] | None = None
    cart_items: list[dict[str, Any]] | None = None
    payment_token: str | None = None
    customer_email: str | None = None

    @property
    def resolved_items(self) -> list[dict[str, Any]]:
        """Accept either field name from the task context."""
        return self.items or self.cart_items or []
```

**Result types** describe what a handler returns (used by downstream `@depends_on`):

```python
class EcommerceValidateCartResult(BaseModel):
    validated_items: list[dict[str, Any]] | None = None
    item_count: int | None = None
    subtotal: float | None = None
    tax: float | None = None
    total: float | None = None
```

All fields are optional with `None` defaults. This is intentional — task context may not include every field, and upstream results may vary. The type system provides structure and IDE autocomplete without brittle required-field failures.

**Validation** with `@model_validator`:

```python
from pydantic import model_validator

class ValidateRefundRequestInput(BaseModel):
    ticket_id: str | None = None
    order_ref: str | None = None
    refund_amount: float | None = None

    @property
    def resolved_ticket_id(self) -> str | None:
        return self.ticket_id or self.order_ref

    @model_validator(mode='after')
    def check_required_fields(self) -> 'ValidateRefundRequestInput':
        if not self.resolved_ticket_id:
            raise PermanentError(
                message="ticket_id or order_ref is required",
                error_code="MISSING_TICKET_ID",
            )
        return self
```

## Accessing Task Context

The `@inputs(Model)` decorator extracts the full task context into a typed Pydantic model. Fields are matched by name from the submitted JSON:

```python
@step_handler("validate_cart")
@inputs(EcommerceOrderInput)
def validate_cart(inputs: EcommerceOrderInput, context: StepContext):
    # inputs.cart_items, inputs.customer_email, etc. are typed fields
    return svc.validate_cart_items(inputs.resolved_items)
```

The `context` parameter provides execution metadata (task UUID, step UUID, step config) but most handlers don't need it directly.

## Working with Dependencies

The `@depends_on` decorator injects typed results from upstream steps. Each entry maps a parameter name to a `("step_name", ResultModel)` tuple:

```python
@step_handler("process_payment")
@depends_on(cart_result=("validate_cart", EcommerceValidateCartResult))
@inputs(EcommerceOrderInput)
def process_payment(
    cart_result: EcommerceValidateCartResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.process_payment(
        payment_token=inputs.payment_token,
        total=cart_result.total or 0.0,
    )
```

Handlers can reference **any ancestor step** in the DAG — not just direct predecessors. Tasker makes all ancestor results available. Here's a convergence handler that accesses three upstream steps:

```python
@step_handler("create_order")
@depends_on(
    cart_result=("validate_cart", EcommerceValidateCartResult),
    payment_result=("process_payment", EcommerceProcessPaymentResult),
    inventory_result=("update_inventory", EcommerceUpdateInventoryResult),
)
@inputs(EcommerceOrderInput)
def create_order(
    cart_result: EcommerceValidateCartResult,
    payment_result: EcommerceProcessPaymentResult,
    inventory_result: EcommerceUpdateInventoryResult,
    inputs: EcommerceOrderInput,
    context: StepContext,
):
    return svc.create_order(
        cart=cart_result, payment=payment_result,
        inventory=inventory_result, customer_email=inputs.customer_email,
    )
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

The handlers are just as concise as the e-commerce ones:

```python
from app.services import data_pipeline as svc
from app.services.types import (
    DataPipelineInput,
    PipelineExtractSalesResult,
    PipelineTransformSalesResult,
    PipelineTransformInventoryResult,
    PipelineTransformCustomersResult,
    PipelineAggregateMetricsResult,
)

# Extract — no dependencies, runs in parallel
@step_handler("extract_sales_data")
@inputs(DataPipelineInput)
def extract_sales_data(inputs: DataPipelineInput, context: StepContext):
    return svc.extract_sales_data(
        source=inputs.source,
        date_range_start=inputs.date_range_start,
        date_range_end=inputs.date_range_end,
        granularity=inputs.granularity,
    )

# Transform — depends on one extract branch
@step_handler("transform_sales")
@depends_on(sales_data=("extract_sales_data", PipelineExtractSalesResult))
def transform_sales(sales_data: PipelineExtractSalesResult, context: StepContext):
    return svc.transform_sales(sales_data=sales_data)

# Aggregate — converges three transform branches
@step_handler("aggregate_metrics")
@depends_on(
    sales_transform=("transform_sales", PipelineTransformSalesResult),
    traffic_transform=("transform_inventory", PipelineTransformInventoryResult),
    inventory_transform=("transform_customers", PipelineTransformCustomersResult),
)
def aggregate_metrics(
    sales_transform: PipelineTransformSalesResult,
    traffic_transform: PipelineTransformInventoryResult,
    inventory_transform: PipelineTransformCustomersResult,
    context: StepContext,
):
    return svc.aggregate_metrics(
        sales_transform=sales_transform,
        traffic_transform=traffic_transform,
        inventory_transform=inventory_transform,
    )
```

Eight handlers, eight service delegations. The pipeline DAG runs three extract steps in parallel, feeds each into a transform, then converges at aggregation and insight generation.

## Error Handling

Raise `PermanentError` or `RetryableError` from your handler or service functions:

```python
from tasker_core.errors import PermanentError, RetryableError

# Non-retryable validation failure
raise PermanentError(
    message="Payment declined: insufficient funds",
    error_code="PAYMENT_DECLINED",
)

# Retryable transient failure
raise RetryableError(
    message="Payment gateway returned an error, will retry",
    error_code="GATEWAY_ERROR",
)
```

Pydantic `@model_validator` errors are also caught and converted to `PermanentError` automatically — invalid input data won't be retried.

## Testing

DSL handlers are plain functions — test them by calling the function directly with mocked inputs:

```python
from unittest.mock import MagicMock, patch

def test_validate_cart():
    context = MagicMock()
    # Mock the inputs that @inputs would inject
    inputs = EcommerceOrderInput(
        cart_items=[{"sku": "SKU-001", "name": "Widget", "quantity": 2, "unit_price": 29.99}]
    )

    with patch("app.services.ecommerce.validate_cart_items") as mock_svc:
        mock_svc.return_value = {"validated_items": [], "total": 64.79}
        result = validate_cart(inputs=inputs, context=context)

    mock_svc.assert_called_once()
    assert result["total"] == 64.79
```

For handlers with dependencies, construct the result models directly:

```python
def test_create_order():
    context = MagicMock()
    cart = EcommerceValidateCartResult(total=64.79, validated_items=[])
    payment = EcommerceProcessPaymentResult(payment_id="pay_abc", transaction_id="txn_xyz")
    inventory = EcommerceUpdateInventoryResult(inventory_log_id="log_123")
    inputs = EcommerceOrderInput(customer_email="test@example.com")

    with patch("app.services.ecommerce.create_order") as mock_svc:
        mock_svc.return_value = {"order_id": "ORD-001"}
        result = create_order(
            cart_result=cart, payment_result=payment,
            inventory_result=inventory, inputs=inputs, context=context,
        )

    assert result["order_id"] == "ORD-001"
```

Because handlers delegate to service functions, you can also test the services directly without any Tasker infrastructure.

## Handler Variants

### API Handler

Adds HTTP client methods with built-in error classification. Currently uses the class-based pattern with `APIMixin`. See [Class-Based Handlers — API Handler](../reference/class-based-handlers.md#api-handler).

### Decision Handler

Adds workflow routing. The DSL provides `@decision_handler`:

```python
from tasker_core.step_handler.functional import decision_handler

@decision_handler("order_routing")
def order_routing(context: StepContext):
    order_type = context.get_input("order_type")
    if order_type == "premium":
        return ["validate_premium", "process_premium"]
    return ["standard_processing"]
```

See [Conditional Workflows](../guides/conditional-workflows.md) for decision handler patterns.

### Batchable Handler

Adds batch processing for splitting large workloads. Uses the class-based pattern due to its stateful nature (cursor management, batch context). See [Class-Based Handlers — Batchable Handler](../reference/class-based-handlers.md#batchable-handler) and [Batch Processing](../guides/batch-processing.md).

## Class-Based Alternative

If you prefer class inheritance, all handler types support a class-based pattern where you extend `StepHandler` and implement `call(context)`. See [Class-Based Handlers](../reference/class-based-handlers.md) for the full reference.

## Next Steps

- [Your First Workflow](first-workflow.md) — Build a multi-step DAG end-to-end
- [Architecture](../architecture/index.md) — System design details
- [FastAPI example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app) — Complete working implementation
