# Data Pipeline Resilience - Setup Scripts

This directory contains scripts to quickly set up and test the data pipeline resilience examples from Chapter 2.

## 🚀 Quick Start

### One-Command Setup (Recommended)
The fastest way to try the example with zero local dependencies:

```bash
# Download and run the setup script
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_02_data_pipeline_resilience/setup-scripts/blog-setup.sh | bash

# Or with custom app name
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_02_data_pipeline_resilience/setup-scripts/blog-setup.sh | bash -s -- --app-name my-pipeline-demo
```

**Requirements:** Docker and Docker Compose only

### Local Setup
If you prefer to run the setup script locally:

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_02_data_pipeline_resilience/setup-scripts/blog-setup.sh -o blog-setup.sh
chmod +x blog-setup.sh

# Run with options
./blog-setup.sh --app-name pipeline-demo --output-dir ./demos
```

## 🛠️ How It Works

### Docker-Based Architecture
The setup script creates a complete Docker environment with:

- **Rails application** with live code reloading
- **PostgreSQL 15** database with sample data
- **Redis 7** for background job processing
- **Sidekiq** for workflow execution
- **All tested code examples** from the GitHub repository

### Integration with Tasker Repository
All code examples are downloaded directly from the tested repository:

```bash
# Task handler from tested examples
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/fixtures/post_02_data_pipeline_resilience/task_handler/customer_analytics_handler.rb

# Step handlers from tested examples
curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/fixtures/post_02_data_pipeline_resilience/step_handlers/extract_orders_handler.rb
```

This ensures the examples are always up-to-date and have passed integration tests.

## 📋 What Gets Created

### Application Structure
```
data-pipeline-demo/
├── docker-compose.yml                          # Docker services configuration
├── Dockerfile                                  # Application container
├── app/
│   ├── tasks/data_pipeline/
│   │   ├── customer_analytics_handler.rb      # Main workflow handler
│   │   └── step_handlers/
│   │       ├── extract_orders_handler.rb      # Parallel data extraction
│   │       ├── transform_customer_metrics_handler.rb  # Data transformation
│   │       └── generate_insights_handler.rb   # Business intelligence
│   └── controllers/
│       └── analytics_controller.rb            # REST API endpoints
├── config/tasker/tasks/
│   └── customer_analytics_handler.yaml        # Workflow configuration
└── spec/integration/
    └── customer_analytics_workflow_spec.rb    # Integration tests
```

### API Endpoints
- `POST /analytics/start` - Start the analytics pipeline
- `GET /analytics/status/:task_id` - Monitor pipeline progress
- `GET /analytics/results/:task_id` - Get generated insights

## 🧪 Testing the Pipeline Resilience

### Start the Application
```bash
cd data-pipeline-demo
docker-compose up
```

Wait for all services to be ready (you'll see "Ready for connections" messages).

### Start Analytics Pipeline
```bash
curl -X POST http://localhost:3000/analytics/start \
  -H 'Content-Type: application/json' \
  -d '{
    "start_date": "2024-01-01",
    "end_date": "2024-01-31",
    "force_refresh": true
  }'
```

### Monitor Pipeline Progress
```bash
# Replace TASK_ID with the actual task ID from the response
curl http://localhost:3000/analytics/status/TASK_ID
```

### Get Pipeline Results
```bash
curl http://localhost:3000/analytics/results/TASK_ID
```

### Test with Different Date Ranges
```bash
curl -X POST http://localhost:3000/analytics/start \
  -H 'Content-Type: application/json' \
  -d '{
    "start_date": "2024-02-01",
    "end_date": "2024-02-28"
  }'
```

## 🔧 Key Features Demonstrated

### Parallel Processing
The pipeline demonstrates parallel data extraction:
- Orders, users, and products are extracted simultaneously
- Transformations wait for their dependencies to complete
- Maximum resource utilization without bottlenecks

### Progress Tracking
Real-time visibility into long-running operations:
- Batch processing with progress updates
- Estimated completion times
- Current operation status

### Intelligent Retry Logic
Different retry strategies for different failure types:
- Database timeouts: 3 retries with exponential backoff
- CRM API failures: 5 retries (external services can be flaky)
- Dashboard updates: 3 retries (eventual consistency)

### Data Quality Assurance
Built-in data validation and quality checks:
- Schema validation for extracted data
- Completeness checks for critical fields
- Anomaly detection for unusual patterns

### Business Intelligence
The pipeline generates actionable insights:
- Customer segmentation and churn risk analysis
- Product performance and inventory optimization
- Revenue analysis and profit margin tracking
- Automated business recommendations

## 🔍 Monitoring and Observability

### Docker Logs
```bash
# View all service logs
docker-compose logs -f

# View specific service logs
docker-compose logs -f web
docker-compose logs -f sidekiq
```

### Pipeline Monitoring
```bash
# Check running pipelines
curl http://localhost:3000/analytics/status/TASK_ID

# View detailed step information
docker-compose exec web rails console
# Then: Tasker::Task.find('task_id').workflow_step_sequences.last.steps
```

### Progress Tracking
Each step provides detailed progress information:
- Records processed vs. total records
- Current batch being processed
- Estimated time remaining
- Data quality metrics

## 🛠️ Customization

### Adding New Data Sources
1. Create a new extraction step handler
2. Add it to the YAML configuration
3. Update transformation steps to use the new data

Example:
```ruby
# Create app/tasks/data_pipeline/step_handlers/extract_inventory_handler.rb
class DataPipeline::StepHandlers::ExtractInventoryHandler < Tasker::StepHandler
  def handle
    # Extract inventory data
    inventory_data = fetch_inventory_data

    # Store results for downstream steps
    step_result['inventory_data'] = inventory_data
    step_result['records_processed'] = inventory_data.count
  end
end
```

### Modifying Business Logic
Update the insight generation in `generate_insights_handler.rb`:

```ruby
# Custom customer segmentation rules
def segment_customers(customer_data)
  customer_data.group_by do |customer|
    case customer['total_spent']
    when 0..100 then 'bronze'
    when 101..500 then 'silver'
    when 501..1000 then 'gold'
    else 'platinum'
    end
  end
end
```

### Adjusting Retry Policies
Update the YAML configuration:

```yaml
# In config/tasker/tasks/customer_analytics_handler.yaml
step_templates:
  - name: extract_orders
    retryable: true
    retry_limit: 5  # Increase retry attempts
    timeout: 3600000  # 1 hour timeout
```

## 🔧 Troubleshooting

### Common Issues

**Docker services won't start:**
- Ensure Docker is running: `docker --version`
- Check for port conflicts: `docker-compose ps`
- Free up resources: `docker system prune`

**Pipeline doesn't start:**
- Ensure all services are healthy: `docker-compose ps`
- Check Sidekiq is running: `docker-compose logs sidekiq`
- Verify database is ready: `docker-compose exec web rails db:migrate:status`

**Steps fail with data errors:**
- Check sample data exists: `docker-compose exec web rails console`
- Verify data quality: Check for null values or invalid formats
- Review step logs: `docker-compose logs -f sidekiq`

**No progress updates:**
- Ensure Redis is running: `docker-compose exec redis redis-cli ping`
- Check step handler implementations include progress tracking
- Verify event subscribers are loaded

### Getting Help

1. **Check service status**: `docker-compose ps`
2. **View logs**: `docker-compose logs -f`
3. **Restart services**: `docker-compose restart`
4. **Clean restart**: `docker-compose down && docker-compose up`

## 🔮 Related Examples

- **Chapter 1**: [E-commerce Reliability](../../post-01-ecommerce-reliability/setup-scripts/) - Foundation patterns
- **Chapter 3**: [Microservices Coordination](../../post-03-microservices-coordination/setup-scripts/) - Service orchestration

## 📖 Learn More

- **Blog Post**: [When Your Data Pipeline Became a Ticking Time Bomb](../blog-post.md)
- **Code Examples**: [GitHub Repository](https://github.com/tasker-systems/tasker/tree/main/spec/blog/fixtures/post_02_data_pipeline_resilience)
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

## 💡 Next Steps

Once you have the pipeline running:

1. **Experiment with failure scenarios** - Stop dependencies mid-processing
2. **Customize the business logic** - Modify customer segmentation rules
3. **Add new data sources** - Extend with additional extractions
4. **Implement real integrations** - Replace mock APIs with real services
5. **Scale the processing** - Test with larger datasets

The patterns demonstrated here scale from simple ETL jobs to enterprise data platforms handling millions of records.
