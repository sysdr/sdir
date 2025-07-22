#!/bin/bash

# Seasonal Traffic Demo - Start Script
# This script starts the entire demo environment including the scaling demo and Prometheus

set -e

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

# Function to check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose > /dev/null 2>&1; then
        print_error "Docker Compose is not installed. Please install Docker Compose and try again."
        exit 1
    fi
    print_success "Docker Compose is available"
}

# Function to create necessary directories
create_directories() {
    print_status "Creating necessary directories..."
    
    mkdir -p logs
    mkdir -p data
    
    print_success "Directories created"
}

# Function to check if services are already running
check_running_services() {
    if docker-compose ps | grep -q "Up"; then
        print_warning "Services are already running. Stopping existing services..."
        docker-compose down
        sleep 2
    fi
}

# Function to start services
start_services() {
    print_status "Starting services with Docker Compose..."
    
    # Build and start services in detached mode
    docker-compose up -d --build
    
    print_success "Services started successfully"
}

# Function to wait for services to be healthy
wait_for_health() {
    print_status "Waiting for services to be healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps | grep -q "healthy"; then
            print_success "All services are healthy!"
            return 0
        fi
        
        print_status "Waiting for services to be healthy... (attempt $attempt/$max_attempts)"
        sleep 5
        attempt=$((attempt + 1))
    done
    
    print_warning "Services may not be fully healthy yet, but continuing..."
}

# Function to display service information
show_service_info() {
    echo
    print_success "🎉 Seasonal Traffic Demo is now running!"
    echo
    echo -e "${GREEN}Services:${NC}"
    echo -e "  • Scaling Demo: ${BLUE}http://localhost:8000${NC}"
    echo -e "  • Prometheus:   ${BLUE}http://localhost:9090${NC}"
    echo
    echo -e "${GREEN}Available endpoints:${NC}"
    echo -e "  • Main Demo:    ${BLUE}http://localhost:8000${NC}"
    echo -e "  • API Metrics:  ${BLUE}http://localhost:8000/api/metrics${NC}"
    echo -e "  • WebSocket:    ${BLUE}ws://localhost:8000/ws${NC}"
    echo
    echo -e "${GREEN}To stop the demo:${NC}"
    echo -e "  • Run: ${BLUE}./stop.sh${NC}"
    echo -e "  • Or:  ${BLUE}docker-compose down${NC}"
    echo
}

# Function to check service logs
show_logs() {
    print_status "Recent logs from services:"
    echo
    docker-compose logs --tail=10
    echo
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Seasonal Traffic Demo - Start${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    
    # Check prerequisites
    check_docker
    check_docker_compose
    
    # Create directories
    create_directories
    
    # Check for running services
    check_running_services
    
    # Start services
    start_services
    
    # Wait for health
    wait_for_health
    
    # Show service information
    show_service_info
    
    # Show recent logs
    show_logs
    
    print_success "Demo environment is ready!"
}

# Run main function
main "$@" 