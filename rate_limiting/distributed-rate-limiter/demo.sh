#!/bin/bash

# Distributed Rate Limiter Demo Script
# This script installs dependencies, builds, runs, and tests the application

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for service to be ready at $url"
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s "$url" >/dev/null 2>&1; then
            print_success "Service is ready!"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts - Service not ready yet..."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "Service failed to start within expected time"
    return 1
}

# Function to run tests
run_tests() {
    print_status "Running tests..."
    
    # Wait a bit for the application to fully initialize
    sleep 5
    
    # Run unit tests
    if [ -f "tests/test_rate_limiters.py" ]; then
        print_status "Running unit tests..."
        python -m pytest tests/test_rate_limiters.py -v
    fi
    
    # Run performance tests
    if [ -f "tests/performance_test.py" ]; then
        print_status "Running performance tests..."
        python tests/performance_test.py
    fi
    
    # Test API endpoints
    print_status "Testing API endpoints..."
    
    # Test token bucket endpoint
    print_status "Testing token bucket endpoint..."
    for i in {1..5}; do
        response=$(curl -s -w "%{http_code}" -o /tmp/response.json http://localhost:5000/api/token-bucket)
        http_code="${response: -3}"
        if [ "$http_code" = "200" ] || [ "$http_code" = "429" ]; then
            print_success "Token bucket endpoint test $i: HTTP $http_code"
        else
            print_error "Token bucket endpoint test $i failed: HTTP $http_code"
        fi
        sleep 0.5
    done
    
    # Test sliding window endpoint
    print_status "Testing sliding window endpoint..."
    for i in {1..5}; do
        response=$(curl -s -w "%{http_code}" -o /tmp/response.json http://localhost:5000/api/sliding-window)
        http_code="${response: -3}"
        if [ "$http_code" = "200" ] || [ "$http_code" = "429" ]; then
            print_success "Sliding window endpoint test $i: HTTP $http_code"
        else
            print_error "Sliding window endpoint test $i failed: HTTP $http_code"
        fi
        sleep 0.5
    done
    
    # Test fixed window endpoint
    print_status "Testing fixed window endpoint..."
    for i in {1..5}; do
        response=$(curl -s -w "%{http_code}" -o /tmp/response.json http://localhost:5000/api/fixed-window)
        http_code="${response: -3}"
        if [ "$http_code" = "200" ] || [ "$http_code" = "429" ]; then
            print_success "Fixed window endpoint test $i: HTTP $http_code"
        else
            print_error "Fixed window endpoint test $i failed: HTTP $http_code"
        fi
        sleep 0.5
    done
    
    # Test stats endpoint
    print_status "Testing stats endpoint..."
    response=$(curl -s -w "%{http_code}" -o /tmp/response.json http://localhost:5000/api/stats)
    http_code="${response: -3}"
    if [ "$http_code" = "200" ]; then
        print_success "Stats endpoint test: HTTP $http_code"
        echo "Stats response:"
        cat /tmp/response.json | python -m json.tool
    else
        print_error "Stats endpoint test failed: HTTP $http_code"
    fi
}

# Main demo function
main() {
    echo "=========================================="
    echo "Distributed Rate Limiter Demo"
    echo "=========================================="
    
    # Check prerequisites
    print_status "Checking prerequisites..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command_exists docker-compose; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    if ! command_exists curl; then
        print_error "curl is not installed. Please install curl first."
        exit 1
    fi
    
    if ! command_exists python; then
        print_error "Python is not installed. Please install Python first."
        exit 1
    fi
    
    print_success "All prerequisites are satisfied"
    
    # Stop any existing containers
    print_status "Stopping any existing containers..."
    docker-compose down --remove-orphans 2>/dev/null || true
    
    # Build the application
    print_status "Building Docker image..."
    docker-compose build --no-cache
    
    if [ $? -eq 0 ]; then
        print_success "Docker image built successfully"
    else
        print_error "Failed to build Docker image"
        exit 1
    fi
    
    # Start the services
    print_status "Starting services..."
    docker-compose up -d
    
    if [ $? -eq 0 ]; then
        print_success "Services started successfully"
    else
        print_error "Failed to start services"
        exit 1
    fi
    
    # Wait for services to be ready
    wait_for_service "http://localhost:5000"
    
    if [ $? -ne 0 ]; then
        print_error "Services failed to start properly"
        docker-compose logs
        exit 1
    fi
    
    # Show service status
    print_status "Service status:"
    docker-compose ps
    
    # Show logs
    print_status "Recent logs:"
    docker-compose logs --tail=20
    
    # Run tests
    run_tests
    
    # Show final status
    echo ""
    echo "=========================================="
    print_success "Demo completed successfully!"
    echo "=========================================="
    echo ""
    echo "Application is running at:"
    echo "  - Web UI: http://localhost:5000"
    echo "  - API endpoints:"
    echo "    - Token Bucket: http://localhost:5000/api/token-bucket"
    echo "    - Sliding Window: http://localhost:5000/api/sliding-window"
    echo "    - Fixed Window: http://localhost:5000/api/fixed-window"
    echo "    - Stats: http://localhost:5000/api/stats"
    echo ""
    echo "Redis is running on: localhost:6379"
    echo ""
    echo "To stop the services, run: ./cleanup.sh"
    echo "To view logs, run: docker-compose logs -f"
    echo ""
}

# Run the main function
main "$@" 