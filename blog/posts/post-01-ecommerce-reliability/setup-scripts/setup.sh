#!/bin/bash

# Setup script for Chapter 1: E-commerce Reliability
# Updated for Tasker v2.6.0 with Docker support

set -e

# Function definitions must come first
function setup_traditional() {
    echo ""
    echo "🛠️ Setting up traditional Rails environment..."
    echo "This requires Ruby 3.2+, Rails 7.2+, PostgreSQL, and Redis."
    echo ""
    
    # Check prerequisites
    echo "🔍 Checking prerequisites..."
    
    if ! command -v ruby >/dev/null 2>&1; then
        echo "❌ Ruby not found. Please install Ruby 3.2+"
        exit 1
    fi
    
    ruby_version=$(ruby -v | grep -o '[0-9]\+\.[0-9]\+' | head -1)
    if ! ruby -e "exit(Gem::Version.new('$ruby_version') >= Gem::Version.new('3.2'))" 2>/dev/null; then
        echo "❌ Ruby 3.2+ required. Found: $ruby_version"
        exit 1
    fi
    
    if ! command -v rails >/dev/null 2>&1; then
        echo "⚠️ Rails not found. Installing..."
        gem install rails
    fi
    
    if ! command -v psql >/dev/null 2>&1; then
        echo "❌ PostgreSQL not found. Please install PostgreSQL"
        echo "   macOS: brew install postgresql"
        echo "   Ubuntu: sudo apt-get install postgresql"
        exit 1
    fi
    
    if ! command -v redis-server >/dev/null 2>&1; then
        echo "❌ Redis not found. Please install Redis"
        echo "   macOS: brew install redis"
        echo "   Ubuntu: sudo apt-get install redis-server"
        exit 1
    fi
    
    echo "✅ Prerequisites satisfied"
    echo ""
    
    curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
        --app-name ecommerce-reliability-demo \
        --tasks ecommerce \
        --non-interactive
    
    cd ecommerce-reliability-demo
    
    echo ""
    echo "✅ Setup complete!"
    echo ""
    echo "🚀 To start the application:"
    echo "   1. Start Redis: redis-server"
    echo "   2. Start Sidekiq: bundle exec sidekiq"
    echo "   3. Start Rails: bundle exec rails server"
    echo ""
    echo "📍 Your application will be at: http://localhost:3000"
}

echo "🛒 Chapter 1: E-commerce Reliability Setup"
echo "========================================"
echo ""
echo "This script sets up a complete e-commerce workflow example"
echo "demonstrating how Tasker handles checkout reliability patterns."
echo ""

# Check for Docker availability
DOCKER_AVAILABLE=false
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    DOCKER_AVAILABLE=true
fi

echo "🏗️ Choose your setup method:"
echo ""
if [ "$DOCKER_AVAILABLE" = true ]; then
    echo "1. 🐳 Docker Setup (Recommended)"
    echo "   - Zero local dependencies"
    echo "   - One-command startup"
    echo "   - Identical across all platforms"
    echo ""
    echo "2. 🔬 Docker + Observability Stack"
    echo "   - Everything from option 1"
    echo "   - Jaeger tracing UI"
    echo "   - Prometheus metrics"
    echo "   - Production-like monitoring"
    echo ""
    echo "3. 🛠️ Traditional Rails Setup"
    echo "   - Local Ruby/Rails development"
    echo "   - Requires PostgreSQL and Redis"
    echo "   - More control over environment"
    echo ""
else
    echo "⚠️  Docker not available - using traditional setup"
    echo ""
    echo "1. 🛠️ Traditional Rails Setup"
    echo "   - Local Ruby/Rails development"
    echo "   - Requires PostgreSQL and Redis"
    echo ""
fi

# Get user choice
if [ "$DOCKER_AVAILABLE" = true ]; then
    read -p "Enter your choice (1-3): " choice
else
    choice=1  # Only option available
fi

case $choice in
    1)
        if [ "$DOCKER_AVAILABLE" = true ]; then
            echo ""
            echo "🐳 Setting up Docker environment..."
            echo "This will create a complete containerized development environment."
            echo ""
            
            curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
                --app-name ecommerce-reliability-demo \
                --tasks ecommerce \
                --docker \
                --non-interactive
            
            cd ecommerce-reliability-demo
            
            echo ""
            echo "🚀 Starting Docker services..."
            ./bin/docker-dev up
            
            echo ""
            echo "✅ Setup complete!"
            echo ""
            echo "📍 Your application is running at:"
            echo "   http://localhost:3000"
            echo ""
            echo "🔧 Useful commands:"
            echo "   ./bin/docker-dev status    # Check service status"
            echo "   ./bin/docker-dev logs      # View logs"
            echo "   ./bin/docker-dev console   # Rails console"
            echo "   ./bin/docker-dev down      # Stop all services"
            echo ""
        else
            setup_traditional
        fi
        ;;
    2)
        echo ""
        echo "🔬 Setting up Docker with full observability stack..."
        echo "This includes Jaeger for tracing and Prometheus for metrics."
        echo ""
        
        curl -fsSL https://raw.githubusercontent.com/tasker-systems/tasker/main/scripts/install-tasker-app.sh | bash -s -- \
            --app-name ecommerce-reliability-demo \
            --tasks ecommerce \
            --docker \
            --with-observability \
            --non-interactive
        
        cd ecommerce-reliability-demo
        
        echo ""
        echo "🚀 Starting full Docker environment..."
        ./bin/docker-dev up-full
        
        echo ""
        echo "✅ Setup complete!"
        echo ""
        echo "📍 Application URLs:"
        echo "   Rails App: http://localhost:3000"
        echo "   Jaeger UI: http://localhost:16686 (distributed tracing)"
        echo "   Prometheus: http://localhost:9090 (metrics collection)"
        echo "   GraphQL: http://localhost:3000/tasker/graphql"
        echo ""
        echo "🔧 Useful commands:"
        echo "   ./bin/docker-dev status    # Check all service status"
        echo "   ./bin/docker-dev logs      # View logs from all services"
        echo "   ./bin/docker-dev validate  # Run integration tests"
        echo "   ./bin/docker-dev down      # Stop all services"
        echo ""
        ;;
    3)
        setup_traditional
        ;;
    *)
        echo "❌ Invalid choice. Please run the script again."
        exit 1
        ;;
esac

echo "📚 Next Steps:"
echo ""
echo "1. 🧪 Try the demo API endpoints:"
echo "   curl -X POST http://localhost:3000/checkout \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"checkout\": {\"cart_items\": [...], \"payment_info\": {...}, \"customer_info\": {...}}}'"
echo ""
echo "2. 📖 Read the blog post to understand the reliability patterns"
echo "3. 🔍 Explore the code examples in the working application"
echo "4. 🎯 Try different failure scenarios to see retry logic in action"
echo ""
echo "Happy coding! 🎉"