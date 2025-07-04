#!/bin/bash

# Test script to verify Docker and GitBook setup
# This script checks prerequisites and runs a basic test

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

# Test Docker installation
test_docker() {
    print_status "Checking Docker installation..."

    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        echo "Install Docker from: https://docs.docker.com/get-docker/"
        return 1
    fi

    print_success "Docker command found"

    # Check if Docker is running
    if ! docker info &> /dev/null; then
        print_error "Docker is not running"
        echo "Start Docker Desktop or Docker daemon"
        return 1
    fi

    print_success "Docker is running"

    # Show Docker version
    docker_version=$(docker --version)
    print_status "Docker version: $docker_version"

    return 0
}

# Test Node.js (for comparison)
test_nodejs() {
    print_status "Checking Node.js installation..."

    if command -v node &> /dev/null; then
        node_version=$(node --version)
        print_status "Node.js version: $node_version"

        if [[ "$node_version" == v14* ]]; then
            print_success "Node.js 14 detected (GitBook compatible)"
        elif [[ "$node_version" == v16* ]]; then
            print_warning "Node.js 16 detected (may work with GitBook)"
        else
            print_warning "Node.js $node_version detected (may not be compatible with GitBook)"
        fi
    else
        print_warning "Node.js not found (not required for Docker approach)"
    fi
}

# Test build script
test_build_script() {
    print_status "Checking build script..."

    if [[ -f "bin/build-site.sh" ]]; then
        print_success "Build script found"

        if [[ -x "bin/build-site.sh" ]]; then
            print_success "Build script is executable"
        else
            print_error "Build script is not executable"
            echo "Run: chmod +x bin/build-site.sh"
            return 1
        fi
    else
        print_error "Build script not found"
        return 1
    fi

    return 0
}

# Test GitBook files
test_gitbook_files() {
    print_status "Checking GitBook files..."

    local required_files=("book.json" "SUMMARY.md" "README.md")
    local missing_files=()

    for file in "${required_files[@]}"; do
        if [[ -f "$file" ]]; then
            print_success "$file found"
        else
            print_error "$file missing"
            missing_files+=("$file")
        fi
    done

    if [[ ${#missing_files[@]} -gt 0 ]]; then
        print_error "Missing required GitBook files: ${missing_files[*]}"
        return 1
    fi

    return 0
}

# Test Docker build (quick test)
test_docker_build() {
    print_status "Testing Docker build (this may take a few minutes)..."

    if docker build -t tasker-gitbook-test . > /dev/null 2>&1; then
        print_success "Docker build successful"

        # Clean up test image
        docker rmi tasker-gitbook-test > /dev/null 2>&1 || true

        return 0
    else
        print_error "Docker build failed"
        echo "Run './bin/build-site.sh build' for detailed error output"
        return 1
    fi
}

# Main test function
run_tests() {
    echo "🧪 GitBook Docker Setup Test"
    echo "============================="
    echo

    local test_count=0
    local passed_count=0

    # Run tests
    local tests=(
        "test_docker"
        "test_nodejs"
        "test_build_script"
        "test_gitbook_files"
    )

    for test in "${tests[@]}"; do
        ((test_count++))
        if $test; then
            ((passed_count++))
        fi
        echo
    done

    # Optional Docker build test (only if Docker is available)
    if command -v docker &> /dev/null && docker info &> /dev/null; then
        print_status "Running optional Docker build test..."
        ((test_count++))
        if test_docker_build; then
            ((passed_count++))
        fi
        echo
    fi

    # Summary
    echo "📊 Test Results"
    echo "==============="
    echo "Tests run: $test_count"
    echo "Passed: $passed_count"
    echo "Failed: $((test_count - passed_count))"
    echo

    if [[ $passed_count -eq $test_count ]]; then
        print_success "All tests passed! 🎉"
        echo
        echo "✅ Ready to build GitBook site:"
        echo "   ./bin/build-site.sh serve"
        echo
        return 0
    else
        print_error "Some tests failed"
        echo
        echo "❌ Please fix the issues above before proceeding"
        echo
        return 1
    fi
}

# Run the tests
run_tests
