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

This creates a handler class that extends `StepHandler` with the standard `call(context)` method.

## Writing a Step Handler

Every Python handler extends `StepHandler` and implements `call`:

```python
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from tasker_core import ErrorType, StepContext, StepHandler, StepHandlerResult


class ValidateCartHandler(StepHandler):
    handler_name = "validate_cart"
    handler_version = "1.0.0"

    TAX_RATE = 0.08

    def call(self, context: StepContext) -> StepHandlerResult:
        cart_items = context.get_input("items") or context.get_input("cart_items")
        if not cart_items or not isinstance(cart_items, list):
            return StepHandlerResult.failure(
                message="Cart is empty or items field is missing",
                error_type=ErrorType.VALIDATION_ERROR,
                retryable=False,
                error_code="EMPTY_CART",
            )

        validated_items: list[dict[str, Any]] = []
        subtotal = 0.0

        for item in cart_items:
            sku = item.get("sku")
            quantity = item.get("quantity", 0)
            unit_price = item.get("unit_price", 0.0)

            if quantity < 1:
                return StepHandlerResult.failure(
                    message=f"Item '{sku}' has invalid quantity: {quantity}",
                    error_type=ErrorType.VALIDATION_ERROR,
                    retryable=False,
                    error_code="INVALID_QUANTITY",
                )

            line_total = round(quantity * unit_price, 2)
            subtotal += line_total
            validated_items.append({
                "sku": sku,
                "name": item.get("name"),
                "quantity": quantity,
                "unit_price": unit_price,
                "line_total": line_total,
            })

        tax = round(subtotal * self.TAX_RATE, 2)
        total = round(subtotal + tax, 2)

        return StepHandlerResult.success(
            result={
                "validated_items": validated_items,
                "item_count": len(validated_items),
                "subtotal": subtotal,
                "tax": tax,
                "total": total,
                "validated_at": datetime.now(timezone.utc).isoformat(),
            },
            metadata={"items_validated": len(validated_items)},
        )
```

The handler receives a `StepContext` and returns a `StepHandlerResult` — either
`StepHandlerResult.success()` or `StepHandlerResult.failure()`.

## Accessing Task Context

Use `get_input()` to read values from the task context (TAS-137 cross-language standard):

```python
# Read a top-level field from the task context
cart_items = context.get_input("cart_items")
customer_email = context.get_input("customer_email")

# Read a nested object
payment_info = context.get_input("payment_info")
token = payment_info.get("token") if payment_info else None
```

## Accessing Dependency Results

Use `get_dependency_result()` to read results from upstream steps. The return value
is auto-unwrapped — you get the result dict directly:

```python
# Get the full result from an upstream step
cart_result = context.get_dependency_result("validate_cart")
total = cart_result.get("total", 0.0)

# Combine data from multiple upstream steps
payment_result = context.get_dependency_result("process_payment")
inventory_result = context.get_dependency_result("update_inventory")
```

## Error Handling

Return `StepHandlerResult.failure()` with an error type and retryable flag:

```python
# Non-retryable validation failure
return StepHandlerResult.failure(
    message="Payment declined: insufficient funds",
    error_type=ErrorType.PERMANENT_ERROR,
    retryable=False,
    error_code="PAYMENT_DECLINED",
)

# Retryable transient failure
return StepHandlerResult.failure(
    message="Payment gateway returned an error, will retry",
    error_type=ErrorType.RETRYABLE_ERROR,
    retryable=True,
    error_code="GATEWAY_ERROR",
)
```

Error types available via the `ErrorType` enum:

- `ErrorType.VALIDATION_ERROR` — Bad input data (non-retryable)
- `ErrorType.PERMANENT_ERROR` — Business logic rejection (non-retryable)
- `ErrorType.RETRYABLE_ERROR` — Transient failure (retryable)
- `ErrorType.HANDLER_ERROR` — Internal handler error

## Task Template Configuration

Generate a task template with `tasker-ctl`:

```bash
tasker-ctl template generate task_template \
  --language python \
  --param name=EcommerceOrderProcessing \
  --param namespace=ecommerce \
  --param handler_callable=ecommerce.task_handlers.OrderProcessingHandler
```

This generates a YAML file defining the workflow. Here is a multi-step example from
the ecommerce example app:

```yaml
name: ecommerce_order_processing
namespace_name: ecommerce_py
version: 1.0.0
description: "Complete e-commerce order processing workflow"
metadata:
  author: FastAPI Example Application
  tags:
    - namespace:ecommerce
    - pattern:order_processing
    - language:python
task_handler:
  callable: ecommerce.task_handlers.OrderProcessingHandler
  initialization:
    input_validation:
      required_fields:
        - items
        - customer_email
system_dependencies:
  primary: default
  secondary: []
input_schema:
  type: object
  required:
    - items
    - customer_email
  properties:
    items:
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
      callable: validate_cart
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
      callable: process_payment
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
      callable: update_inventory
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
      callable: create_order
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
      callable: send_confirmation
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
- **`task_handler`** — The top-level handler and initialization config
- **`system_dependencies`** — External service connections the workflow requires
- **`input_schema`** — JSON Schema validating task input before execution
- **`steps[].handler.callable`** — Python callable name (e.g., `validate_cart` or `handlers.ecommerce.ValidateCartHandler`)
- **`steps[].dependencies`** — DAG edges defining execution order
- **`steps[].retry`** — Per-step retry policy with backoff

## Handler Variants

### API Handler (`step_handler_api`)

```bash
tasker-ctl template generate step_handler_api \
  --language python \
  --param name=FetchUser \
  --param module_name=handlers \
  --param base_url=https://api.example.com
```

Generates a handler that extends `APIMixin` with `StepHandler`, providing HTTP methods
(`get`, `post`, `put`, `delete`) with automatic error classification and retry support
via `httpx`.

### Decision Handler (`step_handler_decision`)

```bash
tasker-ctl template generate step_handler_decision \
  --language python \
  --param name=RouteOrder \
  --param module_name=handlers
```

Generates a handler that extends `DecisionHandler`, providing `decision_success()` for
routing workflows to different downstream step sets based on runtime conditions.

### Batchable Handler (`step_handler_batchable`)

```bash
tasker-ctl template generate step_handler_batchable \
  --language python \
  --param name=ProcessRecords \
  --param module_name=handlers
```

Generates an Analyzer/Worker pattern with two handler classes:
`ProcessRecordsAnalyzerHandler` divides work into cursor ranges, and
`ProcessRecordsWorkerHandler` processes batches in parallel.

## Testing

The template generates a pytest test file alongside the handler:

```python
import uuid
from unittest.mock import MagicMock

from handlers.ecommerce import ValidateCartHandler


class TestValidateCartHandler:
    def test_validates_cart_successfully(self):
        handler = ValidateCartHandler()
        context = MagicMock()
        context.get_input = MagicMock(
            side_effect=lambda key: [
                {"sku": "SKU-001", "name": "Widget", "quantity": 2, "unit_price": 29.99}
            ] if key in ("items", "cart_items") else None
        )

        result = handler.call(context)

        assert result.success is True
        assert result.result["total"] > 0
        assert result.result["item_count"] == 1

    def test_rejects_empty_cart(self):
        handler = ValidateCartHandler()
        context = MagicMock()
        context.get_input = MagicMock(return_value=None)

        result = handler.call(context)

        assert result.success is False
```

Test handlers that use dependency results by configuring `get_dependency_result`:

```python
def test_creates_order_from_upstream_data(self):
    handler = CreateOrderHandler()
    context = MagicMock()
    context.get_input = MagicMock(
        side_effect=lambda key: "test@example.com" if key == "customer_email" else None
    )
    context.get_dependency_result = MagicMock(side_effect=lambda step: {
        "validate_cart": {"total": 64.79, "validated_items": []},
        "process_payment": {"payment_id": "pay_abc", "transaction_id": "txn_xyz"},
        "update_inventory": {"inventory_log_id": "log_123"},
    }.get(step))

    result = handler.call(context)

    assert result.success is True
    assert result.result["order_id"].startswith("ORD-")
```

## Next Steps

- See the [Quick Start Guide](../guides/quick-start.md) for running the full workflow end-to-end
- See [Architecture](../architecture/index.md) for system design details
- Browse the [FastAPI example app](https://github.com/tasker-systems/tasker-contrib/tree/main/examples/fastapi-app) for complete handler implementations
