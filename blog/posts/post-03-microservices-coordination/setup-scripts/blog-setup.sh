#!/bin/bash

# Microservices Coordination Blog Post Demo Setup
# Leverages Docker and GitHub resources for the blog post example
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_03_microservices_coordination/setup-scripts/blog-setup.sh | bash
#
#   Or with options:
#   curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/spec/blog/post_03_microservices_coordination/setup-scripts/blog-setup.sh | bash -s -- --app-name microservices-demo

set -e

# Configuration
GITHUB_REPO="tasker-systems/tasker"
BRANCH="main"
BLOG_FIXTURES_BASE="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/spec/blog/fixtures/post_03_microservices_coordination"
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
    echo -e "${CYAN}🔗 $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Parse command line arguments
APP_NAME="microservices-demo"
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
    mkdir -p app/tasks/user_onboarding/step_handlers
    mkdir -p app/concerns/api_handling
    mkdir -p config/tasker/tasks
    mkdir -p spec/integration

    log_success "Project structure created"
}

# Download blog post examples
download_examples() {
    log_info "Downloading blog post examples from GitHub..."

    # Download task handler
    curl -fsSL "${BLOG_FIXTURES_BASE}/task_handler/create_user_account_handler.rb" \
        -o app/tasks/user_onboarding/create_user_account_handler.rb

    # Download step handlers
    for handler in create_user_account_handler validate_user_info_handler setup_billing_handler configure_preferences_handler; do
        curl -fsSL "${BLOG_FIXTURES_BASE}/step_handlers/${handler}.rb" \
            -o "app/tasks/user_onboarding/step_handlers/${handler}.rb"
    done

    # Download API concerns
    for concern in user_service_api billing_service_api notification_service_api; do
        curl -fsSL "${BLOG_FIXTURES_BASE}/concerns/${concern}.rb" \
            -o "app/concerns/api_handling/${concern}.rb"
    done

    # Download YAML configuration
    curl -fsSL "${BLOG_FIXTURES_BASE}/config/create_user_account_handler.yaml" \
        -o config/tasker/tasks/create_user_account_handler.yaml

    # Download integration tests
    curl -fsSL "${BLOG_FIXTURES_BASE}/integration/user_onboarding_workflow_spec.rb" \
        -o spec/integration/user_onboarding_workflow_spec.rb

    log_success "Blog post examples downloaded"
}

# Create demo controller
create_demo_controller() {
    log_info "Creating demo controller..."

    mkdir -p app/controllers

    cat > app/controllers/user_onboarding_controller.rb << 'EOF'
class UserOnboardingController < ApplicationController
  def create
    task_request = Tasker::Types::TaskRequest.new(
      name: 'create_user_account',
      namespace: 'user_onboarding',
      version: '1.0.0',
      context: onboarding_params.to_h
    )

    task_id = Tasker::HandlerFactory.instance.run_task(task_request)
    task = Tasker::Task.find(task_id)

    render json: {
      success: true,
      task_id: task.task_id,
      status: task.status,
      monitor_url: user_onboarding_status_path(task_id: task.task_id)
    }
  rescue Tasker::ValidationError => e
    render json: {
      success: false,
      error: 'Invalid user onboarding data',
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
        service: step.annotations['service_name'],
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
      final_step = sequence.steps.find { |s| s.name == 'configure_preferences' }

      render json: {
        user_id: final_step&.result&.dig('user_id'),
        account_status: final_step&.result&.dig('account_status'),
        services_configured: final_step&.result&.dig('services_configured') || []
      }
    else
      render json: { error: 'Task not completed yet', status: task.status }
    end
  end

  private

  def onboarding_params
    params.require(:user_onboarding).permit(
      user_info: [:email, :first_name, :last_name, :phone],
      billing_info: [:plan_type, :payment_method, :billing_address],
      preferences: [:newsletter_opt_in, :sms_notifications, :data_sharing_consent]
    )
  end
end
EOF

    log_success "Demo controller created"
}

# Main setup
main() {
    log_header "Microservices Coordination Demo Setup"
    echo
    log_info "This demo showcases Tasker's coordination features through a real microservices workflow"
    echo

    check_dependencies
    setup_project
    download_examples
    create_demo_controller

    echo
    log_success "Microservices demo application created successfully!"
    echo

    # Provide blog-post specific instructions
    log_header "Blog Post Demo Ready!"
    echo
    echo "📚 This demo demonstrates the concepts from:"
    echo "   'When Your Microservices Became a Distributed Monolith'"
    echo
    echo "🚀 Quick Start:"
    echo "   1. Start the application: docker-compose up"
    echo "   2. Wait for all services to be ready"
    echo "   3. The application will be available at http://localhost:3000"
    echo
    echo "🧪 Test the Microservices Coordination Features:"
    echo
    echo "   # Create new user account"
    echo "   curl -X POST http://localhost:3000/user_onboarding \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"user_onboarding\": {\"user_info\": {\"email\": \"test@example.com\", \"first_name\": \"John\", \"last_name\": \"Doe\", \"phone\": \"+1234567890\"}, \"billing_info\": {\"plan_type\": \"premium\", \"payment_method\": \"credit_card\", \"billing_address\": \"123 Main St\"}, \"preferences\": {\"newsletter_opt_in\": true, \"sms_notifications\": false, \"data_sharing_consent\": true}}}'"
    echo
    echo "   # Monitor onboarding progress"
    echo "   curl http://localhost:3000/user_onboarding/status/TASK_ID"
    echo
    echo "   # Get onboarding results"
    echo "   curl http://localhost:3000/user_onboarding/results/TASK_ID"
    echo
    echo "   # Test with different plan types"
    echo "   curl -X POST http://localhost:3000/user_onboarding \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"user_onboarding\": {\"user_info\": {\"email\": \"premium@example.com\", \"first_name\": \"Jane\", \"last_name\": \"Smith\"}, \"billing_info\": {\"plan_type\": \"enterprise\", \"payment_method\": \"invoice\"}, \"preferences\": {\"newsletter_opt_in\": false, \"sms_notifications\": true}}}'"
    echo
    echo "📖 Read the full blog post at:"
    echo "   https://github.com/$GITHUB_REPO/blob/$BRANCH/blog/posts/post-03-microservices-coordination/blog-post.md"
    echo
    echo "🔧 Explore the tested code examples at:"
    echo "   https://github.com/$GITHUB_REPO/tree/$BRANCH/spec/blog/fixtures/post_03_microservices_coordination"
    echo
    echo "🐳 Stop the application:"
    echo "   docker-compose down"
}

# Run main function
main "$@"
