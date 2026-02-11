#!/bin/bash

# Data Pipeline Resilience Blog Post Demo Setup
# Leverages Docker and GitHub resources for the blog post example
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_02_data_pipeline_resilience/setup-scripts/blog-setup.sh | bash
#
#   Or with options:
#   curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_02_data_pipeline_resilience/setup-scripts/blog-setup.sh | bash -s -- --app-name data-pipeline-demo

set -e

# Configuration
GITHUB_REPO="tasker-systems/tasker"
BRANCH="main"
BLOG_FIXTURES_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/spec/blog/fixtures/post_02_data_pipeline_resilience"
DOCKER_COMPOSE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/docker-compose.yml"
DOCKERFILE_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/Dockerfile"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_header() {
    echo -e "${CYAN}📊 $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Parse command line arguments
APP_NAME="data-pipeline-demo"
OUTPUT_DIR="."

while [[ $# -gt 0 ]]; do
    case $1 in
        --app-name)
            APP_NAME="$2"
            shift 2
            ;;
        --app-name=*)
            APP_NAME="${1#*=}"
            shift
            ;;
        --output-dir)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --output-dir=*)
            OUTPUT_DIR="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--app-name NAME] [--output-dir DIR]"
            exit 1
            ;;
    esac
done

# Check dependencies
check_dependencies() {
    log_info "Checking dependencies..."

    if ! command -v docker &> /dev/null; then
        log_error "Docker is required but not installed. Please install Docker first."
        exit 1
    fi

    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is required but not installed. Please install Docker Compose first."
        exit 1
    fi

    if ! command -v curl &> /dev/null; then
        log_error "curl is required but not installed."
        exit 1
    fi

    log_success "All dependencies found"
}

# Create project structure
setup_project() {
    log_info "Setting up project structure..."

    mkdir -p "$OUTPUT_DIR/$APP_NAME"
    cd "$OUTPUT_DIR/$APP_NAME"

    # Download Docker configuration
    log_info "Downloading Docker configuration..."
    curl -fsSL "$DOCKER_COMPOSE_URL" -o docker-compose.yml
    curl -fsSL "$DOCKERFILE_URL" -o Dockerfile

    # Create directories for blog examples
    mkdir -p app/tasks/data_pipeline/step_handlers
    mkdir -p config/tasker/tasks
    mkdir -p spec/integration

    log_success "Project structure created"
}

# Download blog post examples
download_examples() {
    log_info "Downloading blog post examples from GitHub..."

    # Download task handler
    curl -fsSL "${BLOG_FIXTURES_BASE}/task_handler/customer_analytics_handler.rb" \
        -o app/tasks/data_pipeline/customer_analytics_handler.rb

    # Download step handlers
    for handler in extract_orders_handler transform_customer_metrics_handler generate_insights_handler; do
        curl -fsSL "${BLOG_FIXTURES_BASE}/step_handlers/${handler}.rb" \
            -o "app/tasks/data_pipeline/step_handlers/${handler}.rb"
    done

    # Download YAML configuration
    curl -fsSL "${BLOG_FIXTURES_BASE}/config/customer_analytics_handler.yaml" \
        -o config/tasker/tasks/customer_analytics_handler.yaml

    # Download integration tests
    curl -fsSL "${BLOG_FIXTURES_BASE}/integration/customer_analytics_workflow_spec.rb" \
        -o spec/integration/customer_analytics_workflow_spec.rb

    log_success "Blog post examples downloaded"
}

# Create demo controller
create_demo_controller() {
    log_info "Creating demo controller..."

    mkdir -p app/controllers

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
    task = Tasker::Task.find(task_id)

    render json: {
      success: true,
      task_id: task.task_id,
      status: task.status,
      monitor_url: analytics_status_path(task_id: task.task_id)
    }
  rescue Tasker::ValidationError => e
    render json: {
      success: false,
      error: 'Invalid analytics request',
      details: e.message
    }, status: :unprocessable_entity
  end

  def status
    task = Tasker::Task.find(params[:task_id])

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
      task_id: task.task_id,
      status: task.status,
      started_at: task.started_at,
      completed_at: task.completed_at,
      total_duration: task.duration_ms,
      steps: steps
    }
  end

  def results
    task = Tasker::Task.find(params[:task_id])

    if task.status == 'completed'
      sequence = task.workflow_step_sequences.last
      insights_step = sequence.steps.find { |s| s.name == 'generate_insights' }

      render json: insights_step&.result || { error: 'No results available' }
    else
      render json: { error: 'Task not completed yet', status: task.status }
    end
  end

  private

  def analytics_params
    params.permit(:start_date, :end_date, :force_refresh, notification_channels: [])
  end
end
EOF

    log_success "Demo controller created"
}

# Main setup
main() {
    log_header "Data Pipeline Resilience Demo Setup"
    echo
    log_info "This demo showcases Tasker's resilience features through a real data pipeline workflow"
    echo

    check_dependencies
    setup_project
    download_examples
    create_demo_controller

    echo
    log_success "Data pipeline demo application created successfully!"
    echo

    # Provide blog-post specific instructions
    log_header "Blog Post Demo Ready!"
    echo
    echo "📚 This demo demonstrates the concepts from:"
    echo "   'When Your Data Pipeline Became a Ticking Time Bomb'"
    echo
    echo "🚀 Quick Start:"
    echo "   1. Start the application: docker-compose up"
    echo "   2. Wait for all services to be ready"
    echo "   3. The application will be available at http://localhost:3000"
    echo
    echo "🧪 Test the Pipeline Resilience Features:"
    echo
    echo "   # Start analytics pipeline"
    echo "   curl -X POST http://localhost:3000/analytics/start \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"start_date\": \"2024-01-01\", \"end_date\": \"2024-01-31\", \"force_refresh\": true}'"
    echo
    echo "   # Monitor pipeline progress"
    echo "   curl http://localhost:3000/analytics/status/TASK_ID"
    echo
    echo "   # Get pipeline results"
    echo "   curl http://localhost:3000/analytics/results/TASK_ID"
    echo
    echo "   # Test with different date ranges"
    echo "   curl -X POST http://localhost:3000/analytics/start \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"start_date\": \"2024-02-01\", \"end_date\": \"2024-02-28\"}'"
    echo
    echo "📖 Read the full blog post at:"
    echo "   https://github.com/$GITHUB_REPO/blob/$BRANCH/blog/posts/post-02-data-pipeline-resilience/blog-post.md"
    echo
    echo "🔧 Explore the tested code examples at:"
    echo "   https://github.com/$GITHUB_REPO/tree/$BRANCH/spec/blog/fixtures/post_02_data_pipeline_resilience"
    echo
    echo "🐳 Stop the application:"
    echo "   docker-compose down"
}

# Run main function
main "$@"
