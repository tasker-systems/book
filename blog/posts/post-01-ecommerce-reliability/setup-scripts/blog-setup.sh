#!/bin/bash

# E-commerce Blog Post Demo Setup
# Leverages the existing Tasker install-app pattern to create the blog post example
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/jcoletaylor/tasker/main/blog-examples/ecommerce-reliability/setup.sh | bash
#
#   Or with options:
#   curl -fsSL https://raw.githubusercontent.com/jcoletaylor/tasker/main/blog-examples/ecommerce-reliability/setup.sh | bash -s -- --app-name ecommerce-blog-demo

set -e

# Configuration
GITHUB_REPO="jcoletaylor/tasker"
BRANCH="main"
INSTALL_SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/scripts/install-tasker-app.sh"

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

# Main setup
main() {
    log_header "E-commerce Checkout Reliability Demo Setup"
    echo
    log_info "This demo showcases Tasker's reliability features through a real e-commerce checkout workflow"
    echo

    log_info "Downloading and running Tasker application generator..."
    echo

    # Use the existing install-app pattern with e-commerce template
    if command -v curl &> /dev/null; then
        curl -fsSL "$INSTALL_SCRIPT_URL" | bash -s -- \
            --app-name "$APP_NAME" \
            --tasks ecommerce \
            --output-dir "$OUTPUT_DIR" \
            --non-interactive
    else
        echo "❌ curl is required for this setup script"
        exit 1
    fi

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
    echo "   1. cd $OUTPUT_DIR/$APP_NAME"
    echo "   2. Start Redis: redis-server"
    echo "   3. Start Sidekiq: bundle exec sidekiq"
    echo "   4. Start Rails: bundle exec rails server"
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
    echo "   https://github.com/$GITHUB_REPO/blob/$BRANCH/blog-examples/ecommerce-reliability/blog-post.md"
    echo
    echo "🔧 Explore the code patterns at:"
    echo "   https://github.com/$GITHUB_REPO/tree/$BRANCH/blog-examples/ecommerce-reliability/code-examples"
}

# Run main function
main "$@"
