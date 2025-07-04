#!/bin/bash

# GitBook Docker Build Script
# This script builds and serves the GitBook site using Docker for Node.js compatibility

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
IMAGE_NAME="tasker-gitbook"
CONTAINER_NAME="tasker-gitbook-build"
PORT="4000"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to cleanup containers and images
cleanup() {
    print_status "Cleaning up Docker resources..."

    # Stop and remove container if it exists
    if docker ps -a --format 'table {{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_status "Stopping and removing existing container: ${CONTAINER_NAME}"
        docker stop "${CONTAINER_NAME}" >/dev/null 2>&1 || true
        docker rm "${CONTAINER_NAME}" >/dev/null 2>&1 || true
    fi

    # Remove image if it exists (optional - comment out to keep image cached)
    # if docker images --format 'table {{.Repository}}' | grep -q "^${IMAGE_NAME}$"; then
    #     print_status "Removing existing image: ${IMAGE_NAME}"
    #     docker rmi "${IMAGE_NAME}" >/dev/null 2>&1 || true
    # fi
}

# Function to build the Docker image
build_image() {
    print_status "Building Docker image: ${IMAGE_NAME}"

    if docker build -t "${IMAGE_NAME}" .; then
        print_success "Docker image built successfully"
    else
        print_error "Failed to build Docker image"
        exit 1
    fi
}

# Function to build static site
build_static() {
    print_status "Building static GitBook site..."

    # Run container to build static site
    if docker run --rm \
        --name "${CONTAINER_NAME}-build" \
        -v "$(pwd)/_book:/app/_book" \
        "${IMAGE_NAME}" \
        sh -c "cp book-minimal.json book.json && gitbook build"; then
        print_success "Static site built successfully in _book/ directory"
    else
        print_error "Failed to build static site"
        exit 1
    fi
}

# Function to serve the site
serve_site() {
    print_status "Starting GitBook server on port ${PORT}..."
    print_warning "Press Ctrl+C to stop the server"

    # Cleanup any existing container
    cleanup

    # Run container with live reload
    if docker run --rm \
        --name "${CONTAINER_NAME}" \
        -p "${PORT}:4000" \
        -v "$(pwd):/app" \
        "${IMAGE_NAME}" \
        sh -c "cp book-minimal.json book.json && gitbook serve --port 4000 --host 0.0.0.0"; then
        print_success "GitBook server stopped"
    else
        print_error "Failed to start GitBook server"
        exit 1
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  build     Build static GitBook site to _book/ directory"
    echo "  serve     Start development server on port ${PORT}"
    echo "  clean     Clean up Docker resources"
    echo "  help      Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 build     # Build static site"
    echo "  $0 serve     # Start development server"
    echo "  $0 clean     # Clean up Docker resources"
}

# Check if Docker is installed and running
check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        echo "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi

    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

# Main script logic
main() {
    # Check prerequisites
    check_docker

    # Parse command line arguments
    case "${1:-serve}" in
        "build")
            print_status "Building GitBook site with Docker..."
            build_image
            build_static
            print_success "Build complete! Static files are in _book/ directory"
            print_status "You can serve them with: npx http-server _book -p ${PORT}"
            ;;
        "serve")
            print_status "Starting GitBook development server with Docker..."
            build_image
            serve_site
            ;;
        "clean")
            cleanup
            print_success "Docker resources cleaned up"
            ;;
        "help"|"-h"|"--help")
            show_usage
            ;;
        *)
            print_error "Unknown command: $1"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Trap Ctrl+C to cleanup
trap cleanup EXIT

# Run main function
main "$@"
