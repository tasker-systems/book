# Tasker Analytics System

> **📊 Advanced Performance Analytics & Bottleneck Analysis for Production Workflows**
> 
> **New in Tasker v2.7.0** - Comprehensive analytics endpoints with intelligent caching, EventRouter architecture, and performance insights.

The Tasker Analytics system provides real-time performance monitoring and bottleneck analysis for your workflow orchestration. Built on SQL-driven analytics functions with intelligent caching, it delivers sub-100ms analytics responses for production environments.

## 🎯 Quick Start

### Basic Performance Metrics
```bash
# Get system-wide performance overview
curl -H "Authorization: Bearer YOUR_TOKEN" \
  https://your-app.com/tasker/analytics/performance

# Bottleneck analysis for specific namespace
curl -H "Authorization: Bearer YOUR_TOKEN" \
  "https://your-app.com/tasker/analytics/bottlenecks?namespace=ecommerce&period=24"
```

### Ruby API Access
```ruby
# Performance metrics (cached for 90 seconds)
metrics = Tasker::Analytics.performance_metrics

# Bottleneck analysis with filtering
bottlenecks = Tasker::Analytics.bottleneck_analysis(
  namespace: 'data_pipeline',
  period: 24,  # hours
  task_name: 'customer_analytics'
)
```

---

## 📊 Analytics Endpoints

### Performance Analytics (`/analytics/performance`)

**Real-time system health and performance metrics**

```http
GET /tasker/analytics/performance
Authorization: Bearer <token>
```

**Response includes:**
- **System Health Score** - Overall workflow engine health (0-100)
- **Multi-Period Trends** - Performance across 1h, 4h, 24h windows
- **Task Execution Rates** - Completion, failure, and retry statistics
- **Average Processing Times** - Percentile analysis of execution durations
- **Resource Utilization** - Database, Redis, and background job metrics

**Caching:** 90-second TTL with activity-based invalidation

**Example Response:**
```json
{
  "system_health_score": 94.2,
  "performance_trends": {
    "1h": { "completion_rate": 0.96, "avg_duration_ms": 1250 },
    "4h": { "completion_rate": 0.94, "avg_duration_ms": 1180 },
    "24h": { "completion_rate": 0.93, "avg_duration_ms": 1340 }
  },
  "task_statistics": {
    "total_tasks": 15420,
    "completed": 14321,
    "failed": 89,
    "retried": 210
  },
  "processing_times": {
    "p50": 850,
    "p95": 2100,
    "p99": 4200
  }
}
```

### Bottleneck Analysis (`/analytics/bottlenecks`)

**Identify performance bottlenecks and optimization opportunities**

```http
GET /tasker/analytics/bottlenecks?namespace=ecommerce&period=24&task_name=process_order
Authorization: Bearer <token>
```

**Query Parameters:**
- `namespace` (optional) - Filter by specific namespace
- `task_name` (optional) - Filter by specific task name
- `version` (optional) - Filter by task version
- `period` (optional) - Analysis period in hours (default: 24)

**Response includes:**
- **Slowest Tasks** - Tasks taking longest to complete
- **Slowest Steps** - Individual step performance analysis  
- **Error Pattern Analysis** - Common failure points and retry patterns
- **Performance Distribution** - Statistical analysis of execution times
- **Actionable Recommendations** - Specific optimization suggestions

**Caching:** 2-minute TTL with scope-aware cache keys

**Example Response:**
```json
{
  "analysis_period": "24 hours",
  "scope": { "namespace": "ecommerce" },
  "slowest_tasks": [
    {
      "task_name": "process_large_order",
      "avg_duration_ms": 4200,
      "execution_count": 89,
      "failure_rate": 0.02
    }
  ],
  "slowest_steps": [
    {
      "step_name": "payment_processing",
      "task_name": "process_order",
      "avg_duration_ms": 2800,
      "retry_rate": 0.08
    }
  ],
  "error_patterns": [
    {
      "error_type": "NetworkTimeoutError",
      "frequency": 45,
      "affected_steps": ["payment_processing", "inventory_check"]
    }
  ],
  "recommendations": [
    {
      "type": "timeout_optimization",
      "step": "payment_processing",
      "current_timeout": 30,
      "suggested_timeout": 45,
      "rationale": "95th percentile execution time is 42s"
    }
  ]
}
```

---

## 🏗️ Architecture

### SQL-Driven Analytics

Tasker's analytics system leverages high-performance SQL functions for fast data aggregation:

```sql
-- Performance metrics aggregation
SELECT * FROM function_based_analytics_metrics('2024-07-01'::date, 24);

-- Slowest tasks analysis  
SELECT * FROM function_based_slowest_tasks('ecommerce', 24);

-- Step-level bottleneck identification
SELECT * FROM function_based_slowest_steps('process_order', 'ecommerce', 24);
```

### Intelligent Caching Strategy

**Performance Endpoint Caching:**
- **TTL:** 90 seconds
- **Invalidation:** Activity-based (new task completions)
- **Cache Key:** Time-based versioning
- **Headers:** Proper cache control for CDNs

**Bottleneck Endpoint Caching:**
- **TTL:** 2 minutes  
- **Invalidation:** Scope-aware (per namespace/task)
- **Cache Key:** Parameters + timestamp
- **Concurrency:** Thread-safe cache operations

### Authorization & Security

Analytics endpoints follow Tasker's resource-based authorization:

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.telemetry do |tel|
    tel.metrics_auth_required = true  # Enable auth (default: false)
  end
end
```

**Required Permission:** `tasker.analytics:index`

**Authentication Methods:**
- JWT Bearer tokens (recommended for APIs)
- Session-based authentication (for web UIs)
- Service-to-service authentication

---

## 📈 Ruby API Reference

### Performance Metrics

```ruby
# Get comprehensive performance metrics
metrics = Tasker::Functions::FunctionBasedAnalyticsMetrics.call(
  start_date: 1.day.ago,
  hours: 24
)

# Access specific metrics
puts "System health: #{metrics.system_health_score}"
puts "Completion rate: #{metrics.completion_rate}"
puts "Average duration: #{metrics.avg_duration_ms}ms"
```

### Bottleneck Analysis

```ruby
# Analyze slowest tasks in namespace
slow_tasks = Tasker::Functions::FunctionBasedSlowestTasks.call(
  namespace: 'ecommerce',
  hours: 24,
  limit: 10
)

slow_tasks.each do |task|
  puts "#{task.task_name}: #{task.avg_duration_ms}ms (#{task.execution_count} runs)"
end

# Analyze step-level performance
slow_steps = Tasker::Functions::FunctionBasedSlowestSteps.call(
  task_name: 'process_order',
  namespace: 'ecommerce', 
  hours: 24,
  limit: 10
)

slow_steps.each do |step|
  puts "#{step.step_name}: #{step.avg_duration_ms}ms (#{step.retry_rate * 100}% retry rate)"
end
```

### Custom Analytics Queries

```ruby
# Advanced filtering with ActiveRecord scopes
recent_failed_tasks = Tasker::Task
  .failed_since(1.hour.ago)
  .in_namespace('ecommerce')
  .with_task_name('process_order')

# Performance analysis by version
v2_tasks = Tasker::Task
  .completed_since(1.day.ago)
  .with_version('2.1.0')
  .includes(:workflow_steps)

avg_duration = v2_tasks.average(:duration_ms)
```

---

## 🎯 Performance Optimization

### Query Performance

**Built-in Optimizations:**
- Leverages existing database indexes
- Scope-based filtering eliminates N+1 queries
- SQL function aggregation minimizes data transfer
- Efficient ActiveRecord scope chains

**Performance Characteristics:**
- **Sub-100ms Response** - Cached analytics responses
- **Concurrent Safety** - Thread-safe registry operations  
- **Intelligent Invalidation** - Activity-based cache versioning
- **Index Utilization** - Optimized for existing schema

### Scaling Considerations

```ruby
# For high-volume environments, consider:

# 1. Increase cache TTL for stable environments
config.analytics_cache_ttl = 300  # 5 minutes

# 2. Enable read replicas for analytics queries
config.analytics_database_url = ENV['ANALYTICS_READ_REPLICA_URL']

# 3. Implement analytics data retention
config.analytics_retention_days = 90

# 4. Use background aggregation for complex metrics
config.enable_background_analytics = true
```

---

## 🔧 Configuration

### Analytics Configuration

```ruby
# config/initializers/tasker.rb
Tasker.configuration do |config|
  config.analytics do |analytics|
    # Enable/disable analytics endpoints
    analytics.enabled = true
    
    # Cache configuration
    analytics.performance_cache_ttl = 90      # seconds
    analytics.bottlenecks_cache_ttl = 120     # seconds
    
    # Query limits
    analytics.max_bottleneck_results = 50
    analytics.max_analysis_period_hours = 168 # 7 days
    
    # Background processing
    analytics.enable_background_aggregation = false
    analytics.aggregation_interval = 15.minutes
  end
  
  # Authentication requirements
  config.telemetry do |tel|
    tel.metrics_auth_required = true
  end
end
```

### Environment Variables

```bash
# Analytics configuration
TASKER_ANALYTICS_ENABLED=true
TASKER_ANALYTICS_AUTH_REQUIRED=true
TASKER_ANALYTICS_CACHE_TTL=90

# Performance tuning
TASKER_ANALYTICS_MAX_PERIOD_HOURS=168
TASKER_ANALYTICS_BACKGROUND_AGGREGATION=false

# Database optimization
TASKER_ANALYTICS_READ_REPLICA_URL=postgresql://read-replica/db
```

---

## 🧪 Testing Analytics

### RSpec Integration

```ruby
# spec/requests/analytics_spec.rb
describe 'Analytics API', type: :request do
  describe 'GET /tasker/analytics/performance' do
    before { create_list(:completed_task, 10) }
    
    it 'returns performance metrics' do
      get '/tasker/analytics/performance',
          headers: auth_headers
      
      expect(response).to have_http_status(:ok)
      expect(json_response['system_health_score']).to be > 0
      expect(json_response['task_statistics']).to be_present
    end
    
    it 'respects cache headers' do
      get '/tasker/analytics/performance', headers: auth_headers
      expect(response.headers['Cache-Control']).to include('max-age=90')
    end
  end
  
  describe 'GET /tasker/analytics/bottlenecks' do
    it 'filters by namespace' do
      create(:slow_task, namespace: 'ecommerce')
      create(:fast_task, namespace: 'billing')
      
      get '/tasker/analytics/bottlenecks',
          params: { namespace: 'ecommerce' },
          headers: auth_headers
      
      bottlenecks = json_response['slowest_tasks']
      expect(bottlenecks.map { |t| t['namespace'] }).to all(eq('ecommerce'))
    end
  end
end
```

### Load Testing

```ruby
# spec/performance/analytics_performance_spec.rb
describe 'Analytics Performance' do
  it 'responds within 100ms for cached requests' do
    # Warm the cache
    get '/tasker/analytics/performance', headers: auth_headers
    
    # Measure cached response
    start_time = Time.current
    get '/tasker/analytics/performance', headers: auth_headers
    duration = (Time.current - start_time) * 1000
    
    expect(duration).to be < 100  # milliseconds
  end
end
```

---

## 🚀 Production Examples

### Monitoring Dashboard Integration

```ruby
# app/controllers/admin/dashboard_controller.rb
class Admin::DashboardController < ApplicationController
  def show
    @system_health = Tasker::Analytics.performance_metrics
    @recent_bottlenecks = Tasker::Analytics.bottleneck_analysis(
      period: 4,
      limit: 5
    )
  end
end
```

```erb
<!-- app/views/admin/dashboard.html.erb -->
<div class="system-health">
  <h2>System Health: <%= @system_health['system_health_score'] %>%</h2>
  
  <div class="metrics-grid">
    <div class="metric">
      <span class="value"><%= @system_health['task_statistics']['completed'] %></span>
      <span class="label">Tasks Completed (24h)</span>
    </div>
    
    <div class="metric">
      <span class="value"><%= @system_health['processing_times']['p95'] %>ms</span>
      <span class="label">95th Percentile Duration</span>
    </div>
  </div>
</div>

<div class="bottlenecks">
  <h3>Performance Bottlenecks</h3>
  <% @recent_bottlenecks['slowest_tasks'].each do |task| %>
    <div class="bottleneck-item">
      <strong><%= task['task_name'] %></strong>
      <span class="duration"><%= task['avg_duration_ms'] %>ms avg</span>
      <span class="count"><%= task['execution_count'] %> executions</span>
    </div>
  <% end %>
</div>
```

### Alerting Integration

```ruby
# app/jobs/analytics_monitoring_job.rb
class AnalyticsMonitoringJob < ApplicationJob
  def perform
    metrics = Tasker::Analytics.performance_metrics
    
    # Alert on low system health
    if metrics['system_health_score'] < 85
      AlertService.notify(
        "System health degraded: #{metrics['system_health_score']}%",
        severity: :warning
      )
    end
    
    # Alert on high failure rate
    stats = metrics['task_statistics']
    failure_rate = stats['failed'].to_f / stats['total_tasks']
    
    if failure_rate > 0.05  # 5% failure rate
      AlertService.notify(
        "High failure rate detected: #{(failure_rate * 100).round(1)}%",
        severity: :critical
      )
    end
  end
end
```

### Grafana Dashboard Integration

```ruby
# app/controllers/metrics/grafana_controller.rb
class Metrics::GrafanaController < ApplicationController
  def analytics_metrics
    metrics = Tasker::Analytics.performance_metrics
    
    render json: {
      system_health: metrics['system_health_score'],
      completion_rate: metrics['performance_trends']['1h']['completion_rate'],
      avg_duration: metrics['performance_trends']['1h']['avg_duration_ms'],
      p95_duration: metrics['processing_times']['p95'],
      timestamp: Time.current.to_i
    }
  end
  
  def bottleneck_summary
    bottlenecks = Tasker::Analytics.bottleneck_analysis(period: 1)
    
    render json: {
      slowest_task_duration: bottlenecks['slowest_tasks'].first&.dig('avg_duration_ms'),
      error_count: bottlenecks['error_patterns'].sum { |p| p['frequency'] },
      recommendation_count: bottlenecks['recommendations'].size,
      timestamp: Time.current.to_i
    }
  end
end
```

---

## 📚 Related Documentation

- **[Metrics & Performance](METRICS.md)** - Prometheus metrics and performance monitoring
- **[Telemetry & Observability](TELEMETRY.md)** - OpenTelemetry integration and distributed tracing
- **[SQL Functions Reference](SQL_FUNCTIONS.md)** - Complete SQL functions documentation
- **[REST API Reference](REST_API.md)** - Complete HTTP API documentation
- **[Health Monitoring](HEALTH.md)** - Production readiness and health checks

---

*The Analytics system is designed for production environments and scales with your workflow complexity. Start with the basic endpoints and gradually integrate advanced features as your monitoring needs grow.*