#!/bin/bash

# Fanout Demo Start Script
# This script starts the fanout demo application with Docker Compose

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

# Check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose > /dev/null 2>&1; then
        print_error "Docker Compose is not installed. Please install Docker Compose and try again."
        exit 1
    fi
    print_success "Docker Compose is available"
}

# Check if required files exist
check_required_files() {
    local required_files=("docker-compose.yml" "Dockerfile" "app/main.py" "requirements.txt")
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$file" ]]; then
            print_error "Required file not found: $file"
            exit 1
        fi
    done
    print_success "All required files found"
}

# Stop any existing containers
stop_existing() {
    if docker-compose ps | grep -q "Up"; then
        print_warning "Found running containers. Stopping them first..."
        docker-compose down
        sleep 2
    fi
}

# Build and start the application
start_application() {
    print_status "Building and starting the fanout demo application..."
    
    # Build the images
    print_status "Building Docker images..."
    docker-compose build --no-cache
    
    # Start the services
    print_status "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 10
    
    # Check if services are running
    if docker-compose ps | grep -q "Up"; then
        print_success "All services are running"
    else
        print_error "Some services failed to start"
        docker-compose logs
        exit 1
    fi
}

# Check if the application is accessible
check_application() {
    print_status "Checking if the application is accessible..."
    
    local max_attempts=30
    local attempt=1
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -s http://localhost:8080 > /dev/null 2>&1; then
            print_success "Application is accessible at http://localhost:8080"
            return 0
        fi
        
        print_status "Attempt $attempt/$max_attempts: Application not ready yet..."
        sleep 2
        ((attempt++))
    done
    
    print_error "Application failed to become accessible after $max_attempts attempts"
    print_status "Checking container logs..."
    docker-compose logs
    return 1
}

# Display service information
show_info() {
    echo ""
    print_success "Fanout Demo is now running!"
    echo ""
    echo -e "${BLUE}Service Information:${NC}"
    echo "  • Web Application: http://localhost:8080"
    echo "  • Redis: localhost:6379"
    echo ""
    echo -e "${BLUE}Useful Commands:${NC}"
    echo "  • View logs: docker-compose logs -f"
    echo "  • Stop services: ./stop.sh"
    echo "  • Restart services: ./restart.sh"
    echo ""
    print_status "Opening the application in your default browser..."
    
    # Open browser (platform-specific)
    if command -v open > /dev/null 2>&1; then
        # macOS
        open http://localhost:8080
    elif command -v xdg-open > /dev/null 2>&1; then
        # Linux
        xdg-open http://localhost:8080
    elif command -v start > /dev/null 2>&1; then
        # Windows
        start http://localhost:8080
    fi
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Fanout Demo Start Script${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Run checks
    check_docker
    check_docker_compose
    check_required_files
    
    # Stop existing containers
    stop_existing
    
    # Start application
    start_application
    
    # Check if application is accessible
    if check_application; then
        show_info
    else
        print_error "Failed to start the application properly"
        exit 1
    fi
}

# Run main function
main "$@" 