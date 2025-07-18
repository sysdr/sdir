#!/bin/bash

# Global Load Balancer Demo - Restart Script
# System Design Interview Roadmap - Issue #99

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

# Function to stop services
stop_services() {
    print_status "Stopping existing services..."
    
    # Stop services with timeout
    if docker-compose ps --services --filter "status=running" | grep -q .; then
        docker-compose down --timeout 30
        print_success "Services stopped"
    else
        print_warning "No services were running"
    fi
}

# Function to start services
start_services() {
    print_status "Starting services..."
    
    # Build and start services
    docker-compose build --no-cache
    docker-compose up -d
    
    print_success "Services started"
}

# Function to wait for services to be healthy
wait_for_health() {
    print_status "Waiting for services to be healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if docker-compose ps | grep -q "healthy"; then
            print_success "All services are healthy!"
            return 0
        fi
        
        print_status "Waiting for services to be healthy... (attempt $attempt/$max_attempts)"
        sleep 5
        ((attempt++))
    done
    
    print_warning "Services may not be fully healthy yet, but continuing..."
    return 0
}

# Function to show service status
show_status() {
    print_status "Service Status:"
    docker-compose ps
    
    echo ""
    print_status "Recent Logs:"
    docker-compose logs --tail=10
}

# Function to show access information
show_access_info() {
    echo ""
    print_success "Global Load Balancer Demo has been restarted!"
    echo ""
    echo -e "${GREEN}Access URLs:${NC}"
    echo -e "  • Main Application: ${BLUE}http://localhost:5000${NC}"
    echo -e "  • Nginx Proxy:      ${BLUE}http://localhost:8888${NC}"
    echo ""
    echo -e "${GREEN}API Endpoints:${NC}"
    echo -e "  • Health Check:     ${BLUE}http://localhost:5000/health${NC}"
    echo -e "  • Data Centers:     ${BLUE}http://localhost:5000/api/data-centers${NC}"
    echo -e "  • Statistics:       ${BLUE}http://localhost:5000/api/stats${NC}"
    echo ""
    echo -e "${GREEN}Management Commands:${NC}"
    echo -e "  • View logs:        ${BLUE}docker-compose logs -f${NC}"
    echo -e "  • Stop services:    ${BLUE}./stop.sh${NC}"
    echo -e "  • Restart services: ${BLUE}./restart.sh${NC}"
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Global Load Balancer Demo${NC}"
    echo -e "${BLUE}  Restarting Services...${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Check prerequisites
    check_docker
    check_docker_compose
    
    # Stop existing services
    stop_services
    
    # Wait a moment for cleanup
    sleep 2
    
    # Start services
    start_services
    
    # Wait for health
    wait_for_health
    
    # Show status
    show_status
    
    # Show access information
    show_access_info
}

# Run main function
main "$@" 