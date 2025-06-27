#!/bin/bash

# Distributed Security Demo - Cleanup Script
# This script stops all services and cleans up all resources

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

# Function to confirm cleanup
confirm_cleanup() {
    echo ""
    print_warning "This will stop and remove ALL containers, images, and data from the distributed security demo."
    echo ""
    echo "The following will be cleaned up:"
    echo "  • All running containers"
    echo "  • All Docker images"
    echo "  • All volumes"
    echo "  • All networks"
    echo "  • All build cache"
    echo ""
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Cleanup cancelled."
        exit 0
    fi
}

# Function to stop and remove containers
stop_containers() {
    print_status "Stopping all containers..."
    
    if [ -f "docker-compose.yml" ]; then
        if docker-compose down --remove-orphans --volumes; then
            print_success "All containers stopped and removed"
        else
            print_warning "Some containers may not have been stopped properly"
        fi
    else
        print_warning "docker-compose.yml not found, skipping container cleanup"
    fi
}

# Function to remove Docker images
remove_images() {
    print_status "Removing Docker images..."
    
    # Get list of images to remove
    local images=(
        "distributed-security-demo-api-gateway"
        "distributed-security-demo-user-service"
        "distributed-security-demo-order-service"
        "distributed-security-demo-payment-service"
        "distributed-security-demo-security-monitor"
    )
    
    for image in "${images[@]}"; do
        if docker image ls "$image" >/dev/null 2>&1; then
            if docker rmi -f "$image" >/dev/null 2>&1; then
                print_success "Removed image: $image"
            else
                print_warning "Failed to remove image: $image"
            fi
        fi
    done
}

# Function to remove dangling images
remove_dangling_images() {
    print_status "Removing dangling images..."
    
    local dangling_images=$(docker images -f "dangling=true" -q 2>/dev/null || true)
    if [ -n "$dangling_images" ]; then
        if docker rmi -f $dangling_images >/dev/null 2>&1; then
            print_success "Removed dangling images"
        else
            print_warning "Some dangling images could not be removed"
        fi
    else
        print_status "No dangling images found"
    fi
}

# Function to remove unused volumes
remove_volumes() {
    print_status "Removing unused volumes..."
    
    local unused_volumes=$(docker volume ls -q -f "dangling=true" 2>/dev/null || true)
    if [ -n "$unused_volumes" ]; then
        if docker volume rm $unused_volumes >/dev/null 2>&1; then
            print_success "Removed unused volumes"
        else
            print_warning "Some volumes could not be removed"
        fi
    else
        print_status "No unused volumes found"
    fi
}

# Function to remove unused networks
remove_networks() {
    print_status "Removing unused networks..."
    
    # Remove demo-specific networks
    local demo_networks=$(docker network ls --filter "name=distributed-security-demo" -q 2>/dev/null || true)
    if [ -n "$demo_networks" ]; then
        if docker network rm $demo_networks >/dev/null 2>&1; then
            print_success "Removed demo networks"
        else
            print_warning "Some networks could not be removed"
        fi
    fi
}

# Function to clean build cache
clean_build_cache() {
    print_status "Cleaning Docker build cache..."
    
    if docker builder prune -f >/dev/null 2>&1; then
        print_success "Build cache cleaned"
    else
        print_warning "Could not clean build cache"
    fi
}

# Function to clean system resources
clean_system() {
    print_status "Cleaning system resources..."
    
    if docker system prune -f >/dev/null 2>&1; then
        print_success "System resources cleaned"
    else
        print_warning "Could not clean all system resources"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    print_success "🎉 Cleanup completed successfully!"
    echo ""
    echo "📋 What was cleaned:"
    echo "  • All containers stopped and removed"
    echo "  • All demo images removed"
    echo "  • All unused volumes removed"
    echo "  • All unused networks removed"
    echo "  • Build cache cleaned"
    echo "  • System resources optimized"
    echo ""
    echo "💡 To start the demo again, run: ./demo.sh"
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "  Distributed Security Demo Cleanup Script"
    echo "=========================================="
    echo ""
    
    # Check prerequisites
    print_status "Checking prerequisites..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed. Nothing to clean up."
        exit 1
    fi
    
    if ! command_exists docker-compose; then
        print_error "Docker Compose is not installed. Nothing to clean up."
        exit 1
    fi
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        print_error "Docker is not running. Nothing to clean up."
        exit 1
    fi
    
    print_success "Docker is running"
    
    # Confirm cleanup
    confirm_cleanup
    
    # Perform cleanup steps
    stop_containers
    remove_images
    remove_dangling_images
    remove_volumes
    remove_networks
    clean_build_cache
    clean_system
    
    # Show summary
    show_cleanup_summary
}

# Run main function
main "$@" 