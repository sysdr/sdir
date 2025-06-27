#!/bin/bash

# Distributed Security Demo - Setup and Test Script
# This script installs dependencies, builds, starts, and tests the entire system

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
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    print_status "Waiting for $service_name to be ready..."
    
    while [ $attempt -le $max_attempts ]; do
        if curl -s -f "$url" >/dev/null 2>&1; then
            print_success "$service_name is ready!"
            return 0
        fi
        
        echo -n "."
        sleep 2
        attempt=$((attempt + 1))
    done
    
    print_error "$service_name failed to start within $((max_attempts * 2)) seconds"
    return 1
}

# Function to test API endpoints
test_api_endpoints() {
    print_status "Testing API endpoints..."
    
    # Test API Gateway health
    print_status "Testing API Gateway health endpoint..."
    if curl -s -f "https://localhost:8000/health" >/dev/null 2>&1; then
        print_success "API Gateway health check passed"
    else
        print_warning "API Gateway health check failed (this might be expected due to SSL)"
    fi
    
    # Test Security Monitor
    print_status "Testing Security Monitor..."
    if curl -s -f "http://localhost:8080/api/security/status" >/dev/null 2>&1; then
        print_success "Security Monitor is responding"
        # Show security status
        echo "Security Status:"
        curl -s "http://localhost:8080/api/security/status" | python3 -m json.tool 2>/dev/null || echo "Raw response: $(curl -s http://localhost:8080/api/security/status)"
    else
        print_error "Security Monitor is not responding"
    fi
    
    # Test Grafana
    print_status "Testing Grafana..."
    if curl -s -f "http://localhost:3000" >/dev/null 2>&1; then
        print_success "Grafana is accessible"
    else
        print_warning "Grafana might still be starting up"
    fi
    
    # Test Prometheus
    print_status "Testing Prometheus..."
    if curl -s -f "http://localhost:9090" >/dev/null 2>&1; then
        print_success "Prometheus is accessible"
    else
        print_warning "Prometheus might still be starting up"
    fi
}

# Function to show service URLs
show_service_urls() {
    echo ""
    print_success "🎉 Distributed Security Demo is now running!"
    echo ""
    echo "📊 Service URLs:"
    echo "  • API Gateway:     https://localhost:8000"
    echo "  • Security Monitor: http://localhost:8080"
    echo "  • Grafana:         http://localhost:3000"
    echo "  • Prometheus:      http://localhost:9090"
    echo ""
    echo "🔧 Individual Services:"
    echo "  • User Service:    http://localhost:8001"
    echo "  • Order Service:   http://localhost:8002"
    echo "  • Payment Service: http://localhost:8003"
    echo ""
    echo "📋 Useful Commands:"
    echo "  • View logs:       docker-compose logs -f [service-name]"
    echo "  • Stop services:   ./cleanup.sh"
    echo "  • Check status:    docker-compose ps"
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "  Distributed Security Demo Setup Script"
    echo "=========================================="
    echo ""
    
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
    
    print_success "All prerequisites are satisfied"
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
    
    print_success "Docker is running"
    
    # Stop any existing containers
    print_status "Stopping any existing containers..."
    docker-compose down --remove-orphans 2>/dev/null || true
    
    # Build Docker images
    print_status "Building Docker images..."
    if docker-compose build; then
        print_success "Docker images built successfully"
    else
        print_error "Failed to build Docker images"
        exit 1
    fi
    
    # Start services
    print_status "Starting all services..."
    if docker-compose up -d; then
        print_success "All services started successfully"
    else
        print_error "Failed to start services"
        exit 1
    fi
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 10
    
    # Test services
    test_api_endpoints
    
    # Show final status
    print_status "Checking final service status..."
    docker-compose ps
    
    # Show service URLs
    show_service_urls
    
    print_success "Demo setup completed successfully!"
    echo ""
    print_warning "Note: Some services may take a few minutes to fully initialize."
    print_warning "If you encounter SSL certificate warnings, this is expected for the demo."
}

# Run main function
main "$@" 