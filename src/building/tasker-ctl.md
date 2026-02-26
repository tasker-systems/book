# Getting Started with tasker-ctl

`tasker-ctl` is the command-line tool for managing Tasker workflows, generating project scaffolding, and working with configuration. This guide covers the developer-facing features for bootstrapping new projects.

## Initialize Your Project

Run `tasker-ctl init` to create a `.tasker-ctl.toml` configuration file in your project directory:

```bash
tasker-ctl init
```

This creates a `.tasker-ctl.toml` pre-configured with the [tasker-contrib](https://github.com/tasker-systems/tasker-contrib) remote, which provides community templates for all supported languages and default configuration files.

To skip the tasker-contrib remote (e.g., if you only use private templates):

```bash
tasker-ctl init --no-contrib
```

## Fetch Remote Templates

After initialization, fetch the remote templates:

```bash
tasker-ctl remote update
```

This clones the configured remotes to a local cache (`~/.cache/tasker-ctl/remotes/`). Subsequent fetches only pull changes. The cache is checked for freshness automatically and warnings are shown when it becomes stale (default: 24 hours).

## Browse Templates

List all available templates:

```bash
tasker-ctl template list
```

Filter by language:

```bash
tasker-ctl template list --language ruby
tasker-ctl template list --language python
```

Get detailed information about a template:

```bash
tasker-ctl template info step_handler --language ruby
```

## Generate Code from Scaffolding Templates

Generate a step handler from a scaffolding template:

```bash
tasker-ctl template generate step_handler \
  --language ruby \
  --param name=ProcessPayment \
  --output ./app/handlers/
```

This creates handler files using the naming conventions and patterns for your chosen language. Template parameters (like `name`) are transformed automatically — `ProcessPayment` becomes `process_payment` for file names and `ProcessPaymentHandler` for class names.

## Generate Typed Code from Task Templates

The `generate` command reads your task template YAML files and produces typed code — result models and handler scaffolds — in any supported language. This keeps your handler code aligned with the schemas defined in your templates.

```text
tasker-ctl generate <COMMAND>

Commands:
  types    Generate typed result models from step result_schema definitions
  handler  Generate handler scaffolds with typed dependency wiring
```

### Generate Types

Generate typed result models from the `result_schema` defined on each step in a task template:

```bash
tasker-ctl generate types \
  --template config/tasker/templates/ecommerce_order_processing.yaml \
  --language typescript
```

This reads each step's `result_schema` and produces language-idiomatic types. For TypeScript, you get Zod schemas with inferred types:

```typescript
export const EcommerceValidateCartResultSchema = z.object({
  free_shipping: z.boolean(),
  item_count: z.number().int(),
  subtotal: z.number(),
  tax: z.number(),
  total: z.number(),
  validated_items: z.array(EcommerceValidateCartResultValidatedItemsSchema),
  validation_id: z.string(),
  // ...
}).passthrough();

export type EcommerceValidateCartResult = z.infer<typeof EcommerceValidateCartResultSchema>;
```

For Python, you get Pydantic models:

```python
class EcommerceValidateCartResult(BaseModel):
    free_shipping: bool
    item_count: int
    subtotal: float
    total: float
    validated_items: list[EcommerceValidateCartResultValidatedItems]
    validation_id: str
```

To generate types for a single step:

```bash
tasker-ctl generate types \
  --template config/tasker/templates/ecommerce_order_processing.yaml \
  --language python \
  --step validate_cart
```

Supported languages: `typescript` (`ts`), `python` (`py`), `ruby` (`rb`), `rust` (`rs`).

### Generate Handlers

Generate handler scaffolds with typed dependency wiring:

```bash
tasker-ctl generate handler \
  --template config/tasker/templates/ecommerce_order_processing.yaml \
  --language typescript \
  --step process_payment
```

The generator reads the step's `dependencies` from the template and wires them into the handler scaffold:

```typescript
export const ProcessPaymentHandler = defineHandler(
  'Ecommerce::StepHandlers::ProcessPaymentHandler',
  {
    depends: {
      validateCartResult: 'validate_cart'
    },
  },
  async ({ validateCartResult, context }) => {
    // validateCartResult: ValidateCartResult (typed)
    // TODO: implement handler logic
    return {
      amount_charged: 0,
      authorization_code: "",
      currency: "",
      // ...
    };
  }
);
```

The return value stub matches the step's `result_schema`, so you can fill in real logic and the shape is already correct.

To generate handlers for all steps at once, omit `--step`. Add `--with-tests` to also generate test scaffolds:

```bash
tasker-ctl generate handler \
  --template config/tasker/templates/ecommerce_order_processing.yaml \
  --language typescript \
  --with-tests
```

Use `--output` to write to a file instead of stdout:

```bash
tasker-ctl generate types \
  --template config/tasker/templates/ecommerce_order_processing.yaml \
  --language typescript \
  --output src/services/types.ts
```

## Generate Configuration

Generate a deployable configuration file from the base + environment configs:

```bash
# From local config directory
tasker-ctl config generate \
  --context orchestration \
  --environment production \
  --output config/orchestration.toml

# From a remote (tasker-contrib provides default configs)
tasker-ctl config generate \
  --remote tasker-contrib \
  --context orchestration \
  --environment development \
  --output config/orchestration.toml
```

The `config generate` command merges base configuration with environment-specific overrides and strips documentation metadata, producing a clean deployment-ready TOML file.

## Manage Remotes

```bash
tasker-ctl remote list                    # Show configured remotes and cache status
tasker-ctl remote add my-templates URL    # Add a new remote
tasker-ctl remote update                  # Fetch latest for all remotes
tasker-ctl remote update tasker-contrib   # Fetch a specific remote
tasker-ctl remote remove my-templates     # Remove a remote and its cache
```

## Typical Workflow

A new project typically follows this sequence:

```bash
# 1. Initialize CLI configuration
tasker-ctl init

# 2. Fetch community templates
tasker-ctl remote update

# 3. Scaffold a step handler from a template
tasker-ctl template generate step_handler --language python --param name=ValidateOrder

# 4. Scaffold a task template
tasker-ctl template generate task_template --language python \
  --param name=OrderProcessing \
  --param namespace=default \
  --param handler_callable=handlers.validate_order_handler.ValidateOrderHandler

# 5. Generate typed code from your task template
tasker-ctl generate types --template config/tasker/templates/order_processing.yaml --language python
tasker-ctl generate handler --template config/tasker/templates/order_processing.yaml --language python

# 6. Generate infrastructure (uses --plugin for ops templates)
tasker-ctl template generate docker_compose --plugin tasker-contrib-ops --param name=myproject

# 7. Generate environment-specific config (merges base + environment overrides)
tasker-ctl config generate --remote tasker-contrib \
  --context worker --environment development --output config/worker.toml
```

> **Note**: Language templates use `--language` to select the plugin (e.g., `--language ruby` selects `tasker-contrib-rails`). Ops templates use `--plugin tasker-contrib-ops` directly since they are language-independent.

## Next Steps

- [Your First Handler](first-handler.md) — Write a step handler from scratch
- [Your First Workflow](first-workflow.md) — Define a task template and run it
- [Configuration Management](../guides/configuration-management.md) — Understanding the TOML config structure
- [tasker-ctl Architecture](../architecture/tasker-ctl.md) — How the CLI is built
