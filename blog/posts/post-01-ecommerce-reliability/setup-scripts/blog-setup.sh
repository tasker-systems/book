#!/bin/bash

# E-commerce Blog Post Demo Setup
# Leverages Docker and GitHub resources for the blog post example
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_01_ecommerce_reliability/setup-scripts/blog-setup.sh | bash
#
#   Or with options:
#   curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_01_ecommerce_reliability/setup-scripts/blog-setup.sh | bash -s -- --app-name ecommerce-blog-demo

set -e

# Configuration
GITHUB_REPO="tasker-systems/tasker"
BRANCH="main"
BLOG_FIXTURES_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/spec/blog/fixtures/post_01_ecommerce_reliability"
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
    echo -e "${CYAN}🛒 $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Parse command line arguments
APP_NAME="ecommerce-blog-demo"
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
    mkdir -p app/tasks/ecommerce/step_handlers
    mkdir -p app/tasks/ecommerce/models
    mkdir -p config/tasker/tasks
    mkdir -p spec/integration

    log_success "Project structure created"
}

# Download blog post examples
download_examples() {
    log_info "Downloading blog post examples from GitHub..."

    # Download task handler
    curl -fsSL "${BLOG_FIXTURES_BASE}/task_handler/order_processing_handler.rb" \
        -o app/tasks/ecommerce/order_processing_handler.rb

    # Download step handlers
    for handler in validate_cart_handler process_payment_handler update_inventory_handler create_order_handler send_confirmation_handler; do
        curl -fsSL "${BLOG_FIXTURES_BASE}/step_handlers/${handler}.rb" \
            -o "app/tasks/ecommerce/step_handlers/${handler}.rb"
    done

    # Download YAML configuration
    curl -fsSL "${BLOG_FIXTURES_BASE}/config/order_processing_handler.yaml" \
        -o config/tasker/tasks/order_processing_handler.yaml

    # Download models
    for model in order product; do
        curl -fsSL "${BLOG_FIXTURES_BASE}/models/${model}.rb" \
            -o "app/tasks/ecommerce/models/${model}.rb"
    done

    # Download integration tests
    curl -fsSL "${BLOG_FIXTURES_BASE}/integration/order_processing_workflow_spec.rb" \
        -o spec/integration/order_processing_workflow_spec.rb

    log_success "Blog post examples downloaded"
}

# Create demo controller
create_demo_controller() {
    log_info "Creating demo controller..."

    mkdir -p app/controllers

    cat > app/controllers/checkout_controller.rb << 'EOF'
class CheckoutController < ApplicationController
  def create
    task_request = Tasker::Types::TaskRequest.new(
      name: 'process_order',
      namespace: 'ecommerce',
      version: '1.0.0',
      context: checkout_params.to_h
    )

    task_id = Tasker::HandlerFactory.instance.run_task(task_request)
    task = Tasker::Task.find(task_id)

    render json: {
      success: true,
      task_id: task.task_id,
      status: task.status,
      checkout_url: order_status_path(task_id: task.task_id)
    }
  rescue Tasker::ValidationError => e
    render json: {
      success: false,
      error: 'Invalid checkout data',
      details: e.message
    }, status: :unprocessable_entity
  end

  def order_status
    task = Tasker::Task.find(params[:task_id])

    case task.status
    when 'complete'
      order_step = task.get_step_by_name('create_order')
      order_id = order_step.results['order_id']

      render json: {
        status: 'completed',
        order_id: order_id,
        order_number: order_step.results['order_number'],
        total_amount: order_step.results['total_amount']
      }
    when 'error'
      failed_step = task.workflow_steps.where("status = 'error'").first

      render json: {
        status: 'failed',
        failed_step: failed_step&.name,
        retry_url: retry_checkout_path(task_id: task.task_id)
      }
    when 'processing'
      render json: {
        status: 'processing',
        current_step: task.workflow_steps.where("status = 'processing'").first&.name
      }
    end
  end

  private

  def checkout_params
    params.require(:checkout).permit(
      cart_items: [:product_id, :quantity],
      payment_info: [:token, :amount],
      customer_info: [:email, :name]
    )
  end
end
EOF

    log_success "Demo controller created"
}

# Main setup
main() {
    log_header "E-commerce Checkout Reliability Demo Setup"
    echo
    log_info "This demo showcases Tasker's reliability features through a real e-commerce checkout workflow"
    echo

    check_dependencies
    setup_project
    download_examples
    create_demo_controller

    echo
    log_success "E-commerce demo application created successfully!"
    echo

    # Provide blog-post specific instructions
    log_header "Blog Post Demo Ready!"
    echo
    echo "📚 This demo demonstrates the concepts from:"
    echo "   'When Your E-commerce Checkout Became a House of Cards'"
    echo
    echo "🚀 Quick Start:"
    echo "   1. Start the application: docker-compose up"
    echo "   2. Wait for all services to be ready"
    echo "   3. The application will be available at http://localhost:3000"
    echo
    echo "🧪 Test the Reliability Features:"
    echo
    echo "   # Successful checkout"
    echo "   curl -X POST http://localhost:3000/checkout \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"checkout\": {\"cart_items\": [{\"product_id\": 1, \"quantity\": 2}], \"payment_info\": {\"token\": \"test_success_visa\", \"amount\": 100.00}, \"customer_info\": {\"email\": \"test@example.com\", \"name\": \"Test Customer\"}}}'"
    echo
    echo "   # Payment failure (retryable)"
    echo "   curl -X POST http://localhost:3000/checkout \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"checkout\": {\"cart_items\": [{\"product_id\": 2, \"quantity\": 1}], \"payment_info\": {\"token\": \"test_timeout_gateway\", \"amount\": 50.00}, \"customer_info\": {\"email\": \"retry@example.com\", \"name\": \"Retry Test\"}}}'"
    echo
    echo "   # Check workflow status"
    echo "   curl http://localhost:3000/order_status/TASK_ID"
    echo
    echo "📖 Read the full blog post at:"
    echo "   https://github.com/$GITHUB_REPO/blob/$BRANCH/blog/posts/post-01-ecommerce-reliability/blog-post.md"
    echo
    echo "🔧 Explore the tested code examples at:"
    echo "   https://github.com/$GITHUB_REPO/tree/$BRANCH/spec/blog/fixtures/post_01_ecommerce_reliability"
    echo
    echo "🐳 Stop the application:"
    echo "   docker-compose down"
}

# Run main function
main "$@"
