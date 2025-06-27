#!/bin/bash

# Distributed Rate Limiter Cleanup Script
# This script stops and cleans up everything

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

# Function to stop and remove containers
cleanup_containers() {
    print_status "Stopping and removing containers..."
    
    if command_exists docker-compose; then
        # Stop containers gracefully
        docker-compose down --remove-orphans 2>/dev/null || true
        
        # Force stop any remaining containers
        docker-compose kill 2>/dev/null || true
        
        # Remove containers
        docker-compose rm -f 2>/dev/null || true
        
        print_success "Containers stopped and removed"
    else
        print_warning "docker-compose not found, trying docker commands..."
        
        # Try to stop containers by name
        docker stop distributed-rate-limiter_app_1 2>/dev/null || true
        docker stop distributed-rate-limiter_redis_1 2>/dev/null || true
        
        # Remove containers
        docker rm distributed-rate-limiter_app_1 2>/dev/null || true
        docker rm distributed-rate-limiter_redis_1 2>/dev/null || true
        
        print_success "Containers stopped and removed using docker commands"
    fi
}

# Function to remove volumes
cleanup_volumes() {
    print_status "Removing volumes..."
    
    if command_exists docker; then
        # Remove Redis data volume
        docker volume rm distributed-rate-limiter_redis_data 2>/dev/null || true
        
        # Remove any other volumes that might exist
        docker volume ls -q | grep "distributed-rate-limiter" | xargs -r docker volume rm 2>/dev/null || true
        
        print_success "Volumes removed"
    else
        print_warning "Docker not found, skipping volume cleanup"
    fi
}

# Function to remove images
cleanup_images() {
    print_status "Removing Docker images..."
    
    if command_exists docker; then
        # Remove the application image
        docker rmi distributed-rate-limiter_app:latest 2>/dev/null || true
        
        # Remove any dangling images
        docker image prune -f 2>/dev/null || true
        
        print_success "Docker images removed"
    else
        print_warning "Docker not found, skipping image cleanup"
    fi
}

# Function to clean up temporary files
cleanup_temp_files() {
    print_status "Cleaning up temporary files..."
    
    # Remove temporary response files
    rm -f /tmp/response.json 2>/dev/null || true
    
    # Remove Python cache files
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "*.pyo" -delete 2>/dev/null || true
    
    # Remove pytest cache
    rm -rf .pytest_cache 2>/dev/null || true
    
    # Remove coverage files
    rm -f .coverage 2>/dev/null || true
    rm -rf htmlcov 2>/dev/null || true
    
    print_success "Temporary files cleaned up"
}

# Function to clean up network
cleanup_network() {
    print_status "Cleaning up Docker network..."
    
    if command_exists docker; then
        # Remove the default network created by docker-compose
        docker network rm distributed-rate-limiter_default 2>/dev/null || true
        
        # Remove any other networks that might exist
        docker network ls -q | grep "distributed-rate-limiter" | xargs -r docker network rm 2>/dev/null || true
        
        print_success "Docker network cleaned up"
    else
        print_warning "Docker not found, skipping network cleanup"
    fi
}

# Function to check if services are still running
check_running_services() {
    print_status "Checking for running services..."
    
    local running_services=0
    
    # Check if containers are still running
    if command_exists docker; then
        if docker ps --format "table {{.Names}}" | grep -q "distributed-rate-limiter"; then
            print_warning "Some containers are still running:"
            docker ps --format "table {{.Names}}\t{{.Status}}" | grep "distributed-rate-limiter"
            running_services=$((running_services + 1))
        fi
    fi
    
    # Check if ports are still in use
    if command_exists lsof; then
        if lsof -i :5000 >/dev/null 2>&1; then
            print_warning "Port 5000 is still in use:"
            lsof -i :5000
            running_services=$((running_services + 1))
        fi
        
        if lsof -i :6379 >/dev/null 2>&1; then
            print_warning "Port 6379 is still in use:"
            lsof -i :6379
            running_services=$((running_services + 1))
        fi
    fi
    
    if [ $running_services -eq 0 ]; then
        print_success "No running services found"
    else
        print_warning "Some services are still running. You may need to manually stop them."
    fi
}

# Function to show cleanup summary
show_summary() {
    echo ""
    echo "=========================================="
    print_success "Cleanup completed!"
    echo "=========================================="
    echo ""
    echo "The following resources have been cleaned up:"
    echo "  ✓ Docker containers"
    echo "  ✓ Docker volumes"
    echo "  ✓ Docker images"
    echo "  ✓ Docker networks"
    echo "  ✓ Temporary files"
    echo "  ✓ Python cache files"
    echo ""
    echo "To start the demo again, run: ./demo.sh"
    echo ""
}

# Main cleanup function
main() {
    echo "=========================================="
    echo "Distributed Rate Limiter Cleanup"
    echo "=========================================="
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # Confirm cleanup
    echo ""
    print_warning "This will stop and remove all containers, volumes, and images."
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleanup cancelled."
        exit 0
    fi
    
    # Perform cleanup steps
    cleanup_containers
    cleanup_volumes
    cleanup_images
    cleanup_network
    cleanup_temp_files
    
    # Check if anything is still running
    check_running_services
    
    # Show summary
    show_summary
}

# Handle script interruption
trap 'echo ""; print_error "Cleanup interrupted"; exit 1' INT TERM

# Run the main function
main "$@" 