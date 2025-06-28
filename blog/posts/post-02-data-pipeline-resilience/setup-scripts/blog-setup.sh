#!/bin/bash

# Blog Chapter 2: Data Pipeline Resilience Setup Script
# This script sets up the complete data pipeline example from the blog post

set -e

echo "🚀 Setting up Data Pipeline Resilience Demo"
echo "============================================="

# Check if we're in the right location
if [ ! -f "README.md" ]; then
    echo "❌ Please run this script from the blog post directory"
    echo "   Expected location: blog/posts/post-02-data-pipeline-resilience/"
    exit 1
fi

# Create demo application directory
DEMO_DIR="demo-app"
echo "📁 Creating demo application directory: $DEMO_DIR"
mkdir -p $DEMO_DIR
cd $DEMO_DIR

# Initialize Rails app if it doesn't exist
if [ ! -f "Gemfile" ]; then
    echo "🔧 Creating new Rails application..."
    rails new . --database=postgresql --skip-git --skip-bundle
fi

echo "📦 Installing required gems..."

# Add Tasker and other required gems to Gemfile
cat >> Gemfile << 'EOF'

# Tasker workflow engine
gem 'tasker', git: 'https://github.com/jcoletaylor/tasker.git'

# Background job processing
gem 'sidekiq'
gem 'redis'

# Data processing
gem 'faker'

# API integrations (for demo)
gem 'httparty'

# Development and testing
group :development, :test do
  gem 'rspec-rails'
  gem 'factory_bot_rails'
end
EOF

# Install gems
bundle install

# Generate Tasker configuration
echo "⚙️ Setting up Tasker configuration..."
bundle exec rails generate tasker:install

# Create database and run migrations
echo "🗄️ Setting up database..."
bundle exec rails db:create
bundle exec rails db:migrate

# Copy code examples from blog post
echo "📋 Copying workflow code examples..."

# Create directory structure
mkdir -p app/tasks/data_pipeline/step_handlers
mkdir -p app/tasks/data_pipeline/event_subscribers
mkdir -p config/tasker/tasks/data_pipeline

# Copy task handler
cp ../code-examples/task_handler/customer_analytics_handler.rb app/tasks/data_pipeline/

# Copy step handlers
cp ../code-examples/step_handlers/*.rb app/tasks/data_pipeline/step_handlers/

# Create YAML configuration
cat > config/tasker/tasks/data_pipeline/customer_analytics.yaml << 'EOF'
name: customer_analytics
namespace_name: data_pipeline
version: '1.0.0'
description: 'Daily customer analytics data pipeline with parallel processing'

schema:
  type: object
  properties:
    date_range:
      type: object
      properties:
        start_date:
          type: string
          format: date
        end_date:
          type: string
          format: date
    force_refresh:
      type: boolean
      default: false
    notification_channels:
      type: array
      items:
        type: string
      default: ['#data-team']

step_templates:
  - name: extract_orders
    description: 'Extract order data from transactional database'
    handler_class: 'DataPipeline::StepHandlers::ExtractOrdersHandler'
    retryable: true
    retry_limit: 3
    timeout: 1800000  # 30 minutes in ms
    
  - name: extract_users
    description: 'Extract user data from CRM system'
    handler_class: 'DataPipeline::StepHandlers::ExtractUsersHandler'
    retryable: true
    retry_limit: 5
    timeout: 1200000  # 20 minutes in ms
    
  - name: extract_products
    description: 'Extract product data from inventory system'
    handler_class: 'DataPipeline::StepHandlers::ExtractProductsHandler'
    retryable: true
    retry_limit: 3
    timeout: 900000   # 15 minutes in ms
    
  - name: transform_customer_metrics
    description: 'Calculate customer behavior metrics'
    depends_on_step: ['extract_orders', 'extract_users']
    handler_class: 'DataPipeline::StepHandlers::TransformCustomerMetricsHandler'
    retryable: true
    retry_limit: 2
    timeout: 2700000  # 45 minutes in ms
    
  - name: transform_product_metrics
    description: 'Calculate product performance metrics'
    depends_on_step: ['extract_orders', 'extract_products']
    handler_class: 'DataPipeline::StepHandlers::TransformProductMetricsHandler'
    retryable: true
    retry_limit: 2
    timeout: 1800000  # 30 minutes in ms
    
  - name: generate_insights
    description: 'Generate business insights and recommendations'
    depends_on_step: ['transform_customer_metrics', 'transform_product_metrics']
    handler_class: 'DataPipeline::StepHandlers::GenerateInsightsHandler'
    timeout: 1200000  # 20 minutes in ms
    
  - name: update_dashboard
    description: 'Update executive dashboard with new metrics'
    depends_on_step: 'generate_insights'
    handler_class: 'DataPipeline::StepHandlers::UpdateDashboardHandler'
    retryable: true
    retry_limit: 3
    
  - name: send_notifications
    description: 'Send completion notifications to stakeholders'
    depends_on_step: 'update_dashboard'
    handler_class: 'DataPipeline::StepHandlers::SendNotificationsHandler'
    retryable: true
    retry_limit: 5
EOF

# Create demo models and sample data
echo "🏗️ Creating demo models and sample data..."

# Generate models
bundle exec rails generate model User email:string first_name:string last_name:string created_at:datetime marketing_emails_enabled:boolean sms_notifications_enabled:boolean date_of_birth:date city:string state:string country:string last_sign_in_at:datetime

bundle exec rails generate model Product name:string description:text category:string subcategory:string price:decimal cost:decimal stock_quantity:integer reorder_level:integer warehouse_location:string brand:string color:string size:string weight:decimal length:decimal width:decimal height:decimal

bundle exec rails generate model Order customer_id:integer total_amount:decimal subtotal:decimal tax_amount:decimal shipping_amount:decimal status:string payment_method:string created_at:datetime

bundle exec rails generate model OrderItem order:references product:references quantity:integer unit_price:decimal line_total:decimal

# Run migrations
bundle exec rails db:migrate

# Create sample data generator
cat > db/seeds.rb << 'EOF'
require 'faker'

puts "🌱 Creating sample data for data pipeline demo..."

# Create users
puts "Creating users..."
100.times do
  User.create!(
    email: Faker::Internet.email,
    first_name: Faker::Name.first_name,
    last_name: Faker::Name.last_name,
    created_at: Faker::Date.between(from: 6.months.ago, to: Date.current),
    marketing_emails_enabled: [true, false].sample,
    sms_notifications_enabled: [true, false].sample,
    date_of_birth: Faker::Date.birthday(min_age: 18, max_age: 80),
    city: Faker::Address.city,
    state: Faker::Address.state,
    country: 'US',
    last_sign_in_at: Faker::Time.between(from: 3.months.ago, to: Time.current)
  )
end

# Create products
puts "Creating products..."
categories = ['Electronics', 'Clothing', 'Home & Garden', 'Sports', 'Books']
50.times do
  category = categories.sample
  Product.create!(
    name: Faker::Commerce.product_name,
    description: Faker::Lorem.paragraph,
    category: category,
    subcategory: Faker::Commerce.department,
    price: Faker::Commerce.price(range: 10.0..500.0),
    cost: Faker::Commerce.price(range: 5.0..250.0),
    stock_quantity: rand(0..100),
    reorder_level: rand(5..20),
    warehouse_location: "#{Faker::Address.state_abbr}-#{rand(1..10)}",
    brand: Faker::Company.name,
    color: Faker::Color.color_name,
    size: ['S', 'M', 'L', 'XL', 'N/A'].sample,
    weight: rand(0.1..10.0).round(2),
    length: rand(1..50),
    width: rand(1..30),
    height: rand(1..20)
  )
end

# Create orders with order items
puts "Creating orders and order items..."
users = User.all
products = Product.all

200.times do
  order = Order.create!(
    customer_id: users.sample.id,
    created_at: Faker::Date.between(from: 30.days.ago, to: Date.current),
    status: ['completed', 'pending', 'shipped'].sample,
    payment_method: ['credit_card', 'paypal', 'apple_pay'].sample
  )
  
  # Add 1-5 items to each order
  subtotal = 0
  rand(1..5).times do
    product = products.sample
    quantity = rand(1..3)
    unit_price = product.price
    line_total = quantity * unit_price
    subtotal += line_total
    
    OrderItem.create!(
      order: order,
      product: product,
      quantity: quantity,
      unit_price: unit_price,
      line_total: line_total
    )
  end
  
  # Update order totals
  tax_amount = subtotal * 0.08
  shipping_amount = subtotal > 50 ? 0 : 9.99
  total_amount = subtotal + tax_amount + shipping_amount
  
  order.update!(
    subtotal: subtotal,
    tax_amount: tax_amount,
    shipping_amount: shipping_amount,
    total_amount: total_amount
  )
end

puts "✅ Sample data created successfully!"
puts "   - #{User.count} users"
puts "   - #{Product.count} products"
puts "   - #{Order.count} orders"
puts "   - #{OrderItem.count} order items"
EOF

# Seed the database
bundle exec rails db:seed

# Create pipeline monitoring
echo "📊 Setting up pipeline monitoring..."

cat > app/tasks/data_pipeline/event_subscribers/pipeline_monitor.rb << 'EOF'
module DataPipeline
  class PipelineMonitor < Tasker::EventSubscriber::Base
    subscribe_to 'step.started', 'step.completed', 'step.failed', 'task.completed', 'task.failed'
    
    def handle_step_started(event)
      if data_pipeline_task?(event)
        puts "🔄 Starting: #{event[:step_name]} (#{event[:task_id]})"
      end
    end
    
    def handle_step_completed(event)
      if data_pipeline_task?(event)
        duration = event[:duration] || 0
        duration_text = duration > 60000 ? "#{(duration/60000).round(1)}min" : "#{(duration/1000).round(1)}s"
        puts "✅ Completed: #{event[:step_name]} in #{duration_text}"
      end
    end
    
    def handle_step_failed(event)
      if data_pipeline_task?(event)
        puts "❌ Failed: #{event[:step_name]} - #{event[:error]}"
      end
    end
    
    def handle_task_completed(event)
      if data_pipeline_task?(event)
        puts "🎉 Analytics pipeline completed successfully!"
      end
    end
    
    def handle_task_failed(event)
      if data_pipeline_task?(event)
        puts "💥 Analytics pipeline failed: #{event[:error]}"
      end
    end
    
    private
    
    def data_pipeline_task?(event)
      event[:namespace] == 'data_pipeline'
    end
  end
end
EOF

# Create demo controller for easy testing
echo "🎮 Creating demo controller..."

cat > app/controllers/analytics_controller.rb << 'EOF'
class AnalyticsController < ApplicationController
  def start
    task_request = Tasker::Types::TaskRequest.new(
      name: 'customer_analytics',
      namespace: 'data_pipeline',
      version: '1.0.0',
      context: {
        date_range: {
          start_date: params[:start_date] || 30.days.ago.strftime('%Y-%m-%d'),
          end_date: params[:end_date] || Date.current.strftime('%Y-%m-%d')
        },
        force_refresh: params[:force_refresh] == 'true',
        notification_channels: params[:notification_channels] || ['#data-team']
      }
    )
    
    task_id = Tasker::HandlerFactory.instance.run_task(task_request)
    
    render json: {
      status: 'started',
      task_id: task_id,
      message: 'Analytics pipeline started successfully',
      monitor_url: "/analytics/status/#{task_id}"
    }
  end
  
  def status
    task_id = params[:id]
    task = Tasker::Task.find(task_id)
    
    sequence = task.workflow_step_sequences.last
    steps = sequence.steps.order(:created_at).map do |step|
      {
        name: step.name,
        status: step.status,
        progress: step.annotations['progress_message'],
        started_at: step.started_at,
        completed_at: step.completed_at,
        duration: step.duration_ms
      }
    end
    
    render json: {
      task_id: task_id,
      status: task.status,
      started_at: task.started_at,
      completed_at: task.completed_at,
      total_duration: task.duration_ms,
      steps: steps
    }
  end
  
  def results
    task_id = params[:id]
    task = Tasker::Task.find(task_id)
    
    if task.status == 'completed'
      sequence = task.workflow_step_sequences.last
      insights_step = sequence.steps.find { |s| s.name == 'generate_insights' }
      
      render json: insights_step&.result || { error: 'No results available' }
    else
      render json: { error: 'Task not completed yet', status: task.status }
    end
  end
end
EOF

# Add routes
cat >> config/routes.rb << 'EOF'
  
  # Analytics Demo Routes
  post '/analytics/start', to: 'analytics#start'
  get '/analytics/status/:id', to: 'analytics#status'
  get '/analytics/results/:id', to: 'analytics#results'
EOF

# Create a simple test script
cat > test_pipeline.rb << 'EOF'
#!/usr/bin/env ruby

require_relative 'config/environment'

puts "🧪 Testing Data Pipeline..."
puts "==========================="

# Start the analytics pipeline
task_request = Tasker::Types::TaskRequest.new(
  name: 'customer_analytics',
  namespace: 'data_pipeline', 
  version: '1.0.0',
  context: {
    date_range: {
      start_date: 7.days.ago.strftime('%Y-%m-%d'),
      end_date: Date.current.strftime('%Y-%m-%d')
    },
    force_refresh: true,
    notification_channels: ['#data-team']
  }
)

puts "Starting analytics pipeline..."
task_id = Tasker::HandlerFactory.instance.run_task(task_request)
puts "✅ Pipeline started with task ID: #{task_id}"

puts "\nMonitoring progress..."
loop do
  task = Tasker::Task.find(task_id)
  puts "Status: #{task.status}"
  
  if task.status == 'completed'
    puts "🎉 Pipeline completed successfully!"
    
    # Get results
    sequence = task.workflow_step_sequences.last
    insights_step = sequence.steps.find { |s| s.name == 'generate_insights' }
    
    if insights_step&.result
      puts "\n📊 Results Summary:"
      executive_summary = insights_step.result['executive_summary']
      if executive_summary
        overview = executive_summary['period_overview']
        puts "  Revenue: $#{overview['total_revenue']}"
        puts "  Customers: #{overview['total_customers_analyzed']}"
        puts "  Products: #{overview['total_products_analyzed']}"
      end
    end
    break
  elsif task.status == 'failed'
    puts "💥 Pipeline failed!"
    break
  else
    sleep(2)
  end
end
EOF

chmod +x test_pipeline.rb

# Create README with usage instructions
cat > README.md << 'EOF'
# Data Pipeline Resilience Demo

This demo application showcases the data pipeline resilience patterns from the blog post.

## Quick Start

1. **Start the background job processor:**
   ```bash
   bundle exec sidekiq
   ```

2. **Start the Rails server:**
   ```bash
   bundle exec rails server
   ```

3. **Run the pipeline via API:**
   ```bash
   # Start pipeline
   curl -X POST http://localhost:3000/analytics/start \
     -H "Content-Type: application/json" \
     -d '{"start_date": "2024-01-01", "end_date": "2024-01-07"}'
   
   # Check status (replace TASK_ID with actual ID)
   curl http://localhost:3000/analytics/status/TASK_ID
   
   # Get results
   curl http://localhost:3000/analytics/results/TASK_ID
   ```

4. **Or run the test script:**
   ```bash
   ./test_pipeline.rb
   ```

## Features Demonstrated

- **Parallel Data Extraction**: Orders, users, and products extracted simultaneously
- **Dependency Management**: Transformations wait for required extractions
- **Progress Tracking**: Real-time progress updates for long-running operations
- **Smart Retry Logic**: Different retry strategies for different failure types
- **Event-Driven Monitoring**: Real-time notifications and alerts
- **Comprehensive Error Handling**: Graceful failure recovery

## Pipeline Steps

1. **extract_orders** - Extract order data from database
2. **extract_users** - Extract user data from CRM (parallel with orders/products)
3. **extract_products** - Extract product data from inventory (parallel)
4. **transform_customer_metrics** - Calculate customer analytics (depends on orders + users)
5. **transform_product_metrics** - Calculate product analytics (depends on orders + products)
6. **generate_insights** - Generate business insights (depends on both transforms)
7. **update_dashboard** - Update executive dashboards
8. **send_notifications** - Send completion notifications and alerts

## Sample Data

The demo includes:
- 100 users with realistic profiles
- 50 products across multiple categories
- 200 orders with 1-5 items each
- Realistic pricing and inventory data

## Monitoring

The pipeline includes comprehensive monitoring:
- Real-time step progress tracking
- Intelligent alerting based on failure type
- Business insights and recommendations
- Dashboard updates for stakeholders

## Architecture Highlights

- **Resilient Design**: Each step handles failures gracefully
- **Scalable Processing**: Batch processing for large datasets
- **Observable Operations**: Complete visibility into pipeline health
- **Business-Focused**: Actionable insights, not just data processing
EOF

echo ""
echo "✅ Setup Complete!"
echo "=================="
echo ""
echo "🎯 Next Steps:"
echo "1. cd demo-app"
echo "2. bundle exec sidekiq &"
echo "3. bundle exec rails server"
echo "4. ./test_pipeline.rb"
echo ""
echo "🔗 Or use the API endpoints:"
echo "   POST /analytics/start"
echo "   GET  /analytics/status/:id"
echo "   GET  /analytics/results/:id"
echo ""
echo "📚 See demo-app/README.md for full instructions"