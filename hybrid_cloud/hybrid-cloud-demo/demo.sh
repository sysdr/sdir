#!/bin/bash

# Hybrid Cloud Demo Script
# System Design Interview Roadmap - Issue #81

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}🔍 $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check system requirements
check_requirements() {
    print_status "Checking system requirements..."
    
    # Check Docker
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        echo "Visit: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    # Check Docker Compose
    if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        echo "Visit: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker daemon is not running. Please start Docker first."
        exit 1
    fi
    
    # Check Python (for tests)
    if ! command_exists python3; then
        print_warning "Python 3 is not installed. Tests will be skipped."
        SKIP_TESTS=true
    else
        # Check if requests module is available
        if ! python3 -c "import requests" >/dev/null 2>&1; then
            print_warning "Python requests module not found. Installing..."
            pip3 install requests
        fi
    fi
    
    # Check curl
    if ! command_exists curl; then
        print_warning "curl is not installed. Some tests will be skipped."
        SKIP_CURL_TESTS=true
    fi
    
    print_success "System requirements check completed"
}



# Function to build services
build_services() {
    print_status "Building Docker services..."
    
    # Remove any existing containers
    print_status "Cleaning up existing containers..."
    docker-compose down 2>/dev/null || true
    
    # Build services
    print_status "Building services (this may take a few minutes)..."
    docker-compose build --no-cache
    
    print_success "Services built successfully"
}

# Function to start services
start_services() {
    print_status "Starting services..."
    
    # Start services in background
    docker-compose up -d
    
    print_status "Waiting for services to initialize..."
    sleep 15
    
    # Check if services are running
    print_status "Checking service status..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s http://localhost:5000/status >/dev/null 2>&1; then
            print_success "All services are running"
            break
        fi
        
        if [ $attempt -eq $max_attempts ]; then
            print_error "Services failed to start within expected time"
            docker-compose logs
            exit 1
        fi
        
        print_status "Waiting for services... (attempt $attempt/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done
}

# Function to run tests
run_tests() {
    print_status "Running tests..."
    
    if [ "$SKIP_TESTS" = true ]; then
        print_warning "Skipping Python tests (Python not available)"
        return
    fi
    
    # Run the test script
    if [ -f "test_demo.py" ]; then
        python3 test_demo.py
        print_success "Tests completed"
    else
        print_warning "test_demo.py not found, skipping tests"
    fi
}

# Function to run curl tests
run_curl_tests() {
    if [ "$SKIP_CURL_TESTS" = true ]; then
        print_warning "Skipping curl tests (curl not available)"
        return
    fi
    
    print_status "Running API tests with curl..."
    
    # Test gateway status
    if curl -s http://localhost:5000/status >/dev/null; then
        print_success "Gateway status endpoint: OK"
    else
        print_error "Gateway status endpoint: FAILED"
    fi
    
    # Test private cloud health
    if curl -s http://localhost:5001/health >/dev/null; then
        print_success "Private cloud health: OK"
    else
        print_error "Private cloud health: FAILED"
    fi
    
    # Test public cloud health
    if curl -s http://localhost:5002/health >/dev/null; then
        print_success "Public cloud health: OK"
    else
        print_error "Public cloud health: FAILED"
    fi
    
    # Test customer creation
    local customer_response=$(curl -s -X POST http://localhost:5000/api/customers \
        -H "Content-Type: application/json" \
        -d '{"name":"Demo Test","email":"demo@test.com"}')
    
    if echo "$customer_response" | grep -q "id"; then
        print_success "Customer creation: OK"
    else
        print_error "Customer creation: FAILED"
    fi
}

# Function to show service information
show_info() {
    echo ""
    echo "🎉 Hybrid Cloud Demo is ready!"
    echo "================================"
    echo ""
    echo "📊 Dashboard: http://localhost:5000"
    echo "🏢 Private Cloud API: http://localhost:5001"
    echo "☁️  Public Cloud API: http://localhost:5002"
    echo "🗄️  Redis: localhost:6379"
    echo ""
    echo "🎮 Demo Features:"
    echo "• Real-time data synchronization"
    echo "• Network failure simulation"
    echo "• Automatic failover"
    echo "• Service restoration"
    echo "• Live monitoring dashboard"
    echo ""
    echo "🛑 To stop: docker-compose down"
    echo "🧹 To cleanup: ./cleanup.sh"
    echo ""
    echo "📋 Service Status:"
    docker-compose ps
}

# Function to cleanup on exit
cleanup() {
    print_status "Cleaning up..."
}

# Set trap to cleanup on script exit
trap cleanup EXIT

# Main execution
main() {
    echo "🚀 Hybrid Cloud Demo Installation Script"
    echo "========================================"
    echo ""
    
    
    # Run all steps
    check_requirements

    build_services
    start_services
    run_tests
    run_curl_tests
    show_info
    
    echo ""
    print_success "Demo installation and testing completed successfully!"
    echo ""
    print_status "Opening dashboard in 3 seconds..."
    sleep 3
    
    # Try to open the dashboard in browser
    if command_exists open; then
        open http://localhost:5000
    elif command_exists xdg-open; then
        xdg-open http://localhost:5000
    else
        print_status "Please open http://localhost:5000 in your browser"
    fi
}

# Run main function
main "$@" 