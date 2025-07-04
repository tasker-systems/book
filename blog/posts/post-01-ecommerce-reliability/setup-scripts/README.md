# E-commerce Reliability - Setup Scripts

This directory contains scripts to quickly set up and test the e-commerce reliability examples from Chapter 1.

## 🚀 Quick Start

### One-Command Setup (Recommended)
The fastest way to try the example with zero local dependencies:

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_01_ecommerce_reliability/setup-scripts/blog-setup.sh | bash

# Or with custom app name
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_01_ecommerce_reliability/setup-scripts/blog-setup.sh | bash -s -- --app-name my-ecommerce-demo
```

**Requirements:** Docker and Docker Compose only

### Local Setup
If you prefer to run the setup script locally:

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_01_ecommerce_reliability/setup-scripts/blog-setup.sh -o blog-setup.sh
chmod +x blog-setup.sh

# Run with options
./blog-setup.sh --app-name ecommerce-demo --output-dir ./demos
```

## 🛠️ How It Works

### Docker-Based Architecture
The setup script creates a complete Docker environment with:

- **Rails application** with live code reloading
- **PostgreSQL 15** database
- **Redis 7** for background job processing
- **Sidekiq** for workflow execution
- **All tested code examples** from the GitHub repository

### Integration with Tasker Repository
All code examples are downloaded directly from the tested repository:

```bash
# Task handler from tested examples
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/fixtures/post_01_ecommerce_reliability/task_handler/order_processing_handler.rb

# Step handlers from tested examples
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/fixtures/post_01_ecommerce_reliability/step_handlers/validate_cart_handler.rb
```

This ensures the examples are always up-to-date and have passed integration tests.

## 📋 What Gets Created

### Application Structure
```
ecommerce-blog-demo/
├── docker-compose.yml                          # Docker services configuration
├── Dockerfile                                  # Application container
├── app/
│   ├── tasks/ecommerce/
│   │   ├── order_processing_handler.rb        # Main workflow handler
│   │   ├── step_handlers/
│   │   │   ├── validate_cart_handler.rb       # Cart validation with retries
│   │   │   ├── process_payment_handler.rb     # Payment processing
│   │   │   ├── update_inventory_handler.rb    # Inventory management
│   │   │   ├── create_order_handler.rb        # Order creation
│   │   │   └── send_confirmation_handler.rb   # Email confirmation
│   │   └── models/
│   │       ├── order.rb                       # Order model
│   │       └── product.rb                     # Product model
│   └── controllers/
│       └── checkout_controller.rb              # REST API endpoints
├── config/tasker/tasks/
│   └── order_processing_handler.yaml          # Workflow configuration
└── spec/integration/
    └── order_processing_workflow_spec.rb      # Integration tests
```

### API Endpoints
- `POST /checkout` - Start checkout workflow
- `GET /order_status/:task_id` - Monitor order processing

## 🧪 Testing the Reliability Features

### Start the Application
```bash
cd ecommerce-blog-demo
docker-compose up
```

Wait for all services to be ready (you'll see "Ready for connections" messages).

### Test Successful Checkout
```bash
curl -X POST http://localhost:3000/checkout \
  -H 'Content-Type: application/json' \
  -d '{
    "checkout": {
      "cart_items": [{"product_id": 1, "quantity": 2}],
      "payment_info": {"token": "test_success_visa", "amount": 100.00},
      "customer_info": {"email": "test@example.com", "name": "Test Customer"}
    }
  }'
```

### Test Payment Failure (Retryable)
```bash
curl -X POST http://localhost:3000/checkout \
  -H 'Content-Type: application/json' \
  -d '{
    "checkout": {
      "cart_items": [{"product_id": 2, "quantity": 1}],
      "payment_info": {"token": "test_timeout_gateway", "amount": 50.00},
      "customer_info": {"email": "retry@example.com", "name": "Retry Test"}
    }
  }'
```

### Monitor Workflow Status
```bash
# Replace TASK_ID with the actual task ID from the response
curl http://localhost:3000/order_status/TASK_ID
```

## 🔧 Key Features Demonstrated

### Reliability Patterns
- **Smart Retry Logic**: Different retry strategies for different failure types
- **Circuit Breaker**: Prevents cascading failures
- **Graceful Degradation**: Continues processing when possible
- **Timeout Handling**: Prevents hanging operations

### Error Handling
- **Retryable Errors**: Payment timeouts, temporary service unavailability
- **Permanent Errors**: Invalid cart items, insufficient inventory
- **Escalation**: Failed retries trigger alerts and manual intervention

### Workflow Orchestration
- **Step Dependencies**: Each step waits for its prerequisites
- **Parallel Processing**: Independent steps run simultaneously
- **State Management**: Complete workflow state tracking
- **Recovery**: Failed workflows can be resumed from last successful step

## 🔍 Monitoring and Observability

### Docker Logs
```bash
# View all service logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f web
docker-compose logs -f sidekiq
```

### Workflow Monitoring
```bash
# Check running workflows
curl http://localhost:3000/order_status/TASK_ID

# View detailed step information
docker-compose exec web rails console
# Then: Tasker::Task.find('task_id').workflow_step_sequences.last.steps
```

## 🛠️ Customization

### Adding New Products
Edit the step handlers to include your product catalog:

```ruby
# In validate_cart_handler.rb
AVAILABLE_PRODUCTS = {
  1 => { name: 'Widget A', price: 50.00, inventory: 100 },
  2 => { name: 'Widget B', price: 75.00, inventory: 50 },
  # Add your products here
}
```

### Modifying Retry Logic
Update the YAML configuration:

```yaml
# In config/tasker/tasks/order_processing_handler.yaml
step_templates:
  - name: process_payment
    retryable: true
    retry_limit: 5  # Increase retry attempts
    timeout: 30000  # 30 second timeout
```

### Adding New Failure Scenarios
Create new payment tokens in `process_payment_handler.rb`:

```ruby
case payment_token
when 'test_network_error'
  raise Tasker::RetryableError, 'Network timeout - will retry'
when 'test_fraud_detected'
  raise Tasker::PermanentError, 'Fraud detected - will not retry'
end
```

## 🔧 Troubleshooting

### Common Issues

**Docker services won't start:**
- Ensure Docker is running: `docker --version`
- Check for port conflicts: `docker-compose ps`
- Free up resources: `docker system prune`

**Application not responding:**
- Wait for database initialization (30-60 seconds)
- Check logs: `docker-compose logs web`
- Verify all services are healthy: `docker-compose ps`

**Workflows not processing:**
- Ensure Sidekiq is running: `docker-compose logs sidekiq`
- Check Redis connectivity: `docker-compose exec redis redis-cli ping`
- Verify database migrations: `docker-compose exec web rails db:migrate:status`

### Getting Help

1. **Check service status**: `docker-compose ps`
2. **View logs**: `docker-compose logs -f`
3. **Restart services**: `docker-compose restart`
4. **Clean restart**: `docker-compose down && docker-compose up`

## 🔮 Related Examples

- **Chapter 2**: [Data Pipeline Resilience](../../post-02-data-pipeline-resilience/setup-scripts/) - Batch processing patterns
- **Chapter 3**: [Microservices Coordination](../../post-03-microservices-coordination/setup-scripts/) - Service orchestration

## 📖 Learn More

- **Blog Post**: [When Your E-commerce Checkout Became a House of Cards](../blog-post.md)
- **Code Examples**: [GitHub Repository](https://github.com/tasker-systems/tasker/tree/main/spec/blog/fixtures/post_01_ecommerce_reliability)
- **Integration Tests**: See how the examples are tested in the repository

## 🛑 Cleanup

When you're done experimenting:

```bash
# Stop all services
docker-compose down

# Remove all containers and volumes
docker-compose down -v

# Remove downloaded images (optional)
docker image prune
```
