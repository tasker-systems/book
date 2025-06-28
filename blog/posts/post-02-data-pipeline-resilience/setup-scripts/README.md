# Data Pipeline Resilience - Setup Scripts

This directory contains scripts to quickly set up and test the data pipeline resilience examples from Chapter 2.

## Quick Setup

The fastest way to get started:

```bash
# Run the complete setup
./blog-setup.sh
```

This script will:
1. Create a new Rails application
2. Install and configure Tasker
3. Set up the data pipeline workflow
4. Create sample data
5. Configure monitoring and notifications

## What Gets Created

### Application Structure
```
demo-app/
├── app/tasks/data_pipeline/
│   ├── customer_analytics_handler.rb           # Main workflow
│   ├── step_handlers/
│   │   ├── extract_orders_handler.rb           # Parallel data extraction
│   │   ├── extract_users_handler.rb
│   │   ├── extract_products_handler.rb
│   │   ├── transform_customer_metrics_handler.rb
│   │   ├── transform_product_metrics_handler.rb
│   │   ├── generate_insights_handler.rb         # Business intelligence
│   │   ├── update_dashboard_handler.rb          # Dashboard integration
│   │   └── send_notifications_handler.rb       # Smart alerting
│   └── event_subscribers/
│       └── pipeline_monitor.rb                 # Real-time monitoring
├── config/tasker/tasks/data_pipeline/
│   └── customer_analytics.yaml                 # Workflow configuration
└── app/controllers/
    └── analytics_controller.rb                 # REST API endpoints
```

### Sample Data
- **100 users** with realistic profiles and preferences
- **50 products** across multiple categories with inventory
- **200 orders** with realistic purchase patterns
- **Order items** with proper pricing and quantities

### API Endpoints
- `POST /analytics/start` - Start the analytics pipeline
- `GET /analytics/status/:id` - Monitor pipeline progress
- `GET /analytics/results/:id` - Get generated insights

## Testing the Pipeline

### Method 1: Test Script
```bash
cd demo-app
./test_pipeline.rb
```

### Method 2: API Calls
```bash
# Start pipeline
curl -X POST http://localhost:3000/analytics/start \
  -H "Content-Type: application/json" \
  -d '{"start_date": "2024-01-01", "end_date": "2024-01-07"}'

# Monitor progress (replace TASK_ID)
curl http://localhost:3000/analytics/status/TASK_ID

# Get results
curl http://localhost:3000/analytics/results/TASK_ID
```

### Method 3: Rails Console
```ruby
# Start the pipeline
task_request = Tasker::Types::TaskRequest.new(
  name: 'customer_analytics',
  namespace: 'data_pipeline',
  version: '1.0.0',
  context: {
    date_range: {
      start_date: 7.days.ago.strftime('%Y-%m-%d'),
      end_date: Date.current.strftime('%Y-%m-%d')
    }
  }
)

task_id = Tasker::HandlerFactory.instance.run_task(task_request)
```

## Key Features Demonstrated

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

### Event-Driven Monitoring
Comprehensive observability:
- Real-time step progress notifications
- Failure alerting with severity levels
- Business insight generation
- Stakeholder notifications

### Business Intelligence
The pipeline generates actionable insights:
- Customer segmentation and churn risk analysis
- Product performance and inventory optimization
- Revenue analysis and profit margin tracking
- Automated business recommendations

## Customization

### Adding New Data Sources
1. Create a new extraction step handler
2. Add it to the YAML configuration
3. Update transformation steps to use the new data

### Modifying Alert Logic
Edit `send_notifications_handler.rb` to customize:
- Alert severity thresholds
- Notification channels
- Escalation rules

### Changing Business Logic
Modify the insight generation in `generate_insights_handler.rb`:
- Custom customer segmentation rules
- Product performance thresholds
- Recommendation algorithms

## Troubleshooting

### Common Issues

**Pipeline doesn't start:**
- Ensure Sidekiq is running: `bundle exec sidekiq`
- Check Redis is running: `redis-cli ping`
- Verify database migrations: `rails db:migrate`

**Steps fail with database errors:**
- Check PostgreSQL is running
- Verify database credentials in `config/database.yml`
- Ensure sample data exists: `rails db:seed`

**No notifications appear:**
- Check Rails logs for Slack/email simulation messages
- Verify event subscriber is loaded: Check `app/tasks/data_pipeline/event_subscribers/`

### Logs and Monitoring

**Rails Logs:**
```bash
tail -f log/development.log
```

**Sidekiq Logs:**
- Check the Sidekiq web UI (if enabled)
- Monitor background job processing

**Task Status:**
```ruby
# In Rails console
task = Tasker::Task.find(task_id)
task.status
task.workflow_step_sequences.last.steps.map(&:status)
```

## Next Steps

Once you have the pipeline running:

1. **Experiment with failure scenarios** - Stop dependencies mid-processing
2. **Customize the business logic** - Modify customer segmentation rules
3. **Add new data sources** - Extend with additional extractions
4. **Implement real integrations** - Replace mock APIs with real services
5. **Scale the processing** - Test with larger datasets

The patterns demonstrated here scale from simple ETL jobs to enterprise data platforms handling millions of records.

## Related Examples

- **Chapter 1**: [E-commerce Reliability](../../post-01-ecommerce-reliability/setup-scripts/) - Foundation patterns
- **Chapter 3**: [Microservices Coordination](../../post-03-microservices-coordination/setup-scripts/) - API orchestration (coming soon)

---

*This setup demonstrates production-ready patterns used in real data engineering environments. The same patterns scale from startup analytics to enterprise data lakes.*