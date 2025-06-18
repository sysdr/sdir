#!/bin/bash

# Clock Synchronization Observatory Demo Script
# This script builds, tests, and runs the complete observatory system

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

# Function to check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Function to check if required ports are available
check_ports() {
    local ports=(3000 8001 8002 8003 8004 8005)
    local occupied_ports=()
    
    for port in "${ports[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            occupied_ports+=($port)
        fi
    done
    
    if [ ${#occupied_ports[@]} -ne 0 ]; then
        print_warning "The following ports are already in use: ${occupied_ports[*]}"
        print_warning "This might cause conflicts. Consider stopping services using these ports."
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to build Docker images
build_images() {
    print_status "Building Docker images..."
    if docker-compose build --parallel; then
        print_success "Docker images built successfully"
    else
        print_error "Failed to build Docker images"
        exit 1
    fi
}

# Function to start services
start_services() {
    print_status "Starting services..."
    if docker-compose up -d; then
        print_success "Services started successfully"
    else
        print_error "Failed to start services"
        exit 1
    fi
}

# Function to wait for services to be ready
wait_for_services() {
    print_status "Waiting for services to be ready..."
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        local all_ready=true
        
        # Check clock nodes
        for i in {1..3}; do
            if ! curl -s http://localhost:800$i/health > /dev/null 2>&1; then
                all_ready=false
                break
            fi
        done
        
        # Check vector clock service
        if ! curl -s http://localhost:8004/ > /dev/null 2>&1; then
            all_ready=false
        fi
        
        # Check TrueTime service
        if ! curl -s http://localhost:8005/ > /dev/null 2>&1; then
            all_ready=false
        fi
        
        # Check dashboard
        if ! curl -s http://localhost:3000/ > /dev/null 2>&1; then
            all_ready=false
        fi
        
        if [ "$all_ready" = true ]; then
            print_success "All services are ready!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        ((attempt++))
    done
    
    print_error "Services did not become ready within timeout"
    return 1
}

# Function to run tests
run_tests() {
    print_status "Running test suite..."
    cd tests
    
    if python3 test_observatory.py; then
        print_success "All tests passed!"
    else
        print_warning "Some tests failed, but continuing with demo..."
    fi
    
    cd ..
}

# Function to show service status
show_status() {
    print_status "Service Status:"
    echo "=================="
    
    # Clock nodes
    for i in {1..3}; do
        if curl -s http://localhost:800$i/health > /dev/null 2>&1; then
            print_success "Clock Node $i: Running (http://localhost:800$i)"
        else
            print_error "Clock Node $i: Not responding"
        fi
    done
    
    # Vector clock service
    if curl -s http://localhost:8004/ > /dev/null 2>&1; then
        print_success "Vector Clock Service: Running (http://localhost:8004)"
    else
        print_error "Vector Clock Service: Not responding"
    fi
    
    # TrueTime service
    if curl -s http://localhost:8005/ > /dev/null 2>&1; then
        print_success "TrueTime Service: Running (http://localhost:8005)"
    else
        print_error "TrueTime Service: Not responding"
    fi
    
    # Dashboard
    if curl -s http://localhost:3000/ > /dev/null 2>&1; then
        print_success "Dashboard: Running (http://localhost:3000)"
    else
        print_error "Dashboard: Not responding"
    fi
}

# Function to run interactive demo
run_demo() {
    print_status "Starting interactive demo..."
    echo
    echo "Clock Synchronization Observatory Demo"
    echo "======================================"
    echo
    echo "Available endpoints:"
    echo "  • Dashboard: http://localhost:3000"
    echo "  • Clock Node 1: http://localhost:8001"
    echo "  • Clock Node 2: http://localhost:8002"
    echo "  • Clock Node 3: http://localhost:8003"
    echo "  • Vector Clock Service: http://localhost:8004"
    echo "  • TrueTime Service: http://localhost:8005"
    echo
    echo "Demo commands you can try:"
    echo "  • curl http://localhost:8001/time"
    echo "  • curl http://localhost:8002/time"
    echo "  • curl http://localhost:8003/time"
    echo "  • curl -X POST http://localhost:8004/reset"
    echo "  • curl -X POST http://localhost:8004/event -H 'Content-Type: application/json' -d '{\"node_id\": 1, \"event_type\": \"local\", \"data\": {\"message\": \"demo\"}}'"
    echo "  • curl http://localhost:8005/now"
    echo
    echo "Press Ctrl+C to stop the demo and clean up"
    echo
    
    # Keep the script running
    while true; do
        sleep 1
    done
}

# Function to cleanup
cleanup() {
    print_status "Cleaning up..."
    docker-compose down
    print_success "Cleanup completed"
}

# Main execution
main() {
    echo "Clock Synchronization Observatory Demo"
    echo "======================================"
    echo
    
    # Check prerequisites
    check_docker
    check_ports
    
    # Build and start
    build_images
    start_services
    
    # Wait for services
    if ! wait_for_services; then
        print_error "Failed to start services properly"
        cleanup
        exit 1
    fi
    
    # Show status
    show_status
    
    # Run tests
    run_tests
    
    # Run demo
    run_demo
}

# Trap Ctrl+C to cleanup
trap cleanup INT

# Run main function
main 