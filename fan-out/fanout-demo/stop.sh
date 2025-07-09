#!/bin/bash

# Fanout Demo Stop Script
# This script stops the fanout demo application and cleans up resources

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

# Check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose > /dev/null 2>&1; then
        print_error "Docker Compose is not installed."
        exit 1
    fi
}

# Check if containers are running
check_running_containers() {
    if ! docker-compose ps | grep -q "Up"; then
        print_warning "No running containers found for this project."
        return 1
    fi
    return 0
}

# Stop the application gracefully
stop_application() {
    print_status "Stopping fanout demo application..."
    
    # Stop containers gracefully
    print_status "Stopping containers..."
    docker-compose down --timeout 30
    
    # Check if containers were stopped
    if docker-compose ps | grep -q "Up"; then
        print_warning "Some containers are still running. Force stopping..."
        docker-compose down --timeout 0
    fi
    
    print_success "All containers stopped"
}

# Clean up resources
cleanup_resources() {
    print_status "Cleaning up resources..."
    
    # Remove stopped containers
    print_status "Removing stopped containers..."
    docker container prune -f > /dev/null 2>&1 || true
    
    # Remove unused networks
    print_status "Removing unused networks..."
    docker network prune -f > /dev/null 2>&1 || true
    
    # Remove unused images (optional - commented out to preserve images)
    # print_status "Removing unused images..."
    # docker image prune -f > /dev/null 2>&1 || true
    
    print_success "Cleanup completed"
}

# Show cleanup options
show_cleanup_options() {
    echo ""
    print_status "Cleanup Options:"
    echo "  • Remove volumes (data): docker-compose down -v"
    echo "  • Remove images: docker-compose down --rmi all"
    echo "  • Remove everything: docker-compose down -v --rmi all"
    echo ""
    print_status "To start the application again, run: ./start.sh"
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Fanout Demo Stop Script${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Check Docker Compose
    check_docker_compose
    
    # Check if containers are running
    if ! check_running_containers; then
        print_warning "No containers to stop."
        show_cleanup_options
        exit 0
    fi
    
    # Stop application
    stop_application
    
    # Cleanup resources
    cleanup_resources
    
    # Show cleanup options
    show_cleanup_options
    
    print_success "Fanout demo has been stopped successfully!"
}

# Run main function
main "$@" 