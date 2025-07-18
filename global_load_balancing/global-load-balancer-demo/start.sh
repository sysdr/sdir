#!/bin/bash

# Global Load Balancer Demo - Start Script
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

# Function to check if required files exist
check_required_files() {
    local required_files=(
        "docker-compose.yml"
        "Dockerfile"
        "app/main.py"
        "requirements.txt"
        "configs/nginx.conf"
        "templates/index.html"
        "static/css/style.css"
        "static/js/app.js"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Required file not found: $file"
            exit 1
        fi
    done
    print_success "All required files found"
}

# Function to stop any existing containers
stop_existing_containers() {
    print_status "Stopping any existing containers..."
    docker-compose down --remove-orphans > /dev/null 2>&1 || true
    print_success "Existing containers stopped"
}

# Function to build and start services
start_services() {
    print_status "Building and starting services..."
    
    # Build the images
    print_status "Building Docker images..."
    docker-compose build --no-cache
    
    # Start the services
    print_status "Starting services..."
    docker-compose up -d
    
    print_success "Services started successfully"
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

# Function to display service status
show_status() {
    print_status "Service Status:"
    docker-compose ps
    
    echo ""
    print_status "Container Logs:"
    docker-compose logs --tail=10
}

# Function to display access information
show_access_info() {
    echo ""
    print_success "Global Load Balancer Demo is now running!"
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
    echo ""
    print_status "Press Ctrl+C to stop the services"
}

# Function to handle cleanup on script exit
cleanup() {
    print_status "Cleaning up..."
    # No cleanup needed for start script
}

# Set up trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Global Load Balancer Demo${NC}"
    echo -e "${BLUE}  Starting Services...${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Check prerequisites
    check_docker
    check_docker_compose
    check_required_files
    
    # Stop existing containers
    stop_existing_containers
    
    # Start services
    start_services
    
    # Wait for health
    wait_for_health
    
    # Show status
    show_status
    
    # Show access information
    show_access_info
    
    # Keep script running and show logs
    print_status "Following logs (press Ctrl+C to stop)..."
    docker-compose logs -f
}

# Run main function
main "$@" 