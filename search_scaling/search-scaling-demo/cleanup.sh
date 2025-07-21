#!/bin/bash

# Search Scaling Demo - Cleanup Script
# This script stops all services and cleans up the demo environment

set -e  # Exit on any error

echo "🧹 Cleaning up Search Scaling Demo"
echo "=================================="

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

# Function to check if services are running
check_services_running() {
    if docker-compose ps --services | grep -q .; then
        return 0
    else
        return 1
    fi
}

# Function to stop all services gracefully
stop_services() {
    print_status "Stopping all services..."
    
    if check_services_running; then
        # Stop services gracefully
        docker-compose stop
        
        # Wait a moment for graceful shutdown
        sleep 3
        
        # Force stop if still running
        docker-compose kill 2>/dev/null || true
        
        print_success "All services stopped"
    else
        print_warning "No services were running"
    fi
}

# Function to remove containers and networks
remove_containers() {
    print_status "Removing containers and networks..."
    
    # Remove containers, networks, and volumes
    docker-compose down -v --remove-orphans
    
    # Remove any orphaned containers
    docker container prune -f 2>/dev/null || true
    
    print_success "Containers and networks removed"
}

# Function to clean up Docker images
cleanup_images() {
    print_status "Cleaning up Docker images..."
    
    # Remove the demo application image
    docker rmi search-scaling-demo_search-app 2>/dev/null || true
    
    # Remove any dangling images
    docker image prune -f 2>/dev/null || true
    
    print_success "Docker images cleaned up"
}

# Function to clean up volumes
cleanup_volumes() {
    print_status "Cleaning up volumes..."
    
    # Remove demo volumes
    docker volume rm search-scaling-demo_es_data 2>/dev/null || true
    docker volume rm search-scaling-demo_redis_data 2>/dev/null || true
    docker volume rm search-scaling-demo_postgres_data 2>/dev/null || true
    
    # Remove any dangling volumes
    docker volume prune -f 2>/dev/null || true
    
    print_success "Volumes cleaned up"
}

# Function to clean up local files
cleanup_local_files() {
    print_status "Cleaning up local files..."
    
    # Remove build marker
    rm -f .build_completed 2>/dev/null || true
    
    # Remove temporary files
    rm -f /tmp/search_performance_results.txt 2>/dev/null || true
    
    # Clean up logs (optional - uncomment if you want to remove logs)
    # rm -rf logs/* 2>/dev/null || true
    
    print_success "Local files cleaned up"
}

# Function to check for any remaining resources
check_remaining_resources() {
    print_status "Checking for remaining resources..."
    
    # Check for any remaining containers
    local remaining_containers=$(docker ps -a --filter "name=search-" --format "table {{.Names}}" | grep -v "NAMES" | wc -l)
    if [ "$remaining_containers" -gt 0 ]; then
        print_warning "Found $remaining_containers remaining containers"
        docker ps -a --filter "name=search-"
    fi
    
    # Check for any remaining volumes
    local remaining_volumes=$(docker volume ls --filter "name=search-scaling-demo" --format "table {{.Name}}" | grep -v "NAME" | wc -l)
    if [ "$remaining_volumes" -gt 0 ]; then
        print_warning "Found $remaining_volumes remaining volumes"
        docker volume ls --filter "name=search-scaling-demo"
    fi
    
    # Check for any remaining networks
    local remaining_networks=$(docker network ls --filter "name=search-scaling-demo" --format "table {{.Name}}" | grep -v "NAME" | wc -l)
    if [ "$remaining_networks" -gt 0 ]; then
        print_warning "Found $remaining_networks remaining networks"
        docker network ls --filter "name=search-scaling-demo"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    print_success "🎉 Cleanup completed successfully!"
    echo ""
    echo "📋 Cleanup Summary:"
    echo "   • All services stopped"
    echo "   • Containers removed"
    echo "   • Networks cleaned up"
    echo "   • Volumes removed"
    echo "   • Images cleaned up"
    echo "   • Local files cleaned up"
    echo ""
    echo "💡 To restart the demo:"
    echo "   • Run './build.sh' to rebuild"
    echo "   • Run './start-demo.sh' to start"
    echo "   • Or use './demo.sh' for the complete experience"
    echo ""
}

# Function to force cleanup (emergency option)
force_cleanup() {
    print_warning "Performing force cleanup..."
    
    # Force remove all containers with search- prefix
    docker ps -a --filter "name=search-" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
    
    # Force remove all volumes with search-scaling-demo prefix
    docker volume ls --filter "name=search-scaling-demo" --format "{{.Name}}" | xargs -r docker volume rm -f 2>/dev/null || true
    
    # Force remove all networks with search-scaling-demo prefix
    docker network ls --filter "name=search-scaling-demo" --format "{{.ID}}" | xargs -r docker network rm -f 2>/dev/null || true
    
    print_success "Force cleanup completed"
}

# Main cleanup function
main() {
    echo ""
    print_status "Starting comprehensive cleanup..."
    echo ""
    
    # Check if Docker is running
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker and try again."
        exit 1
    fi
    
    # Check if we're in the right directory
    if [ ! -f "docker-compose.yml" ]; then
        print_error "docker-compose.yml not found. Please run this script from the project root directory."
        exit 1
    fi
    
    # Perform cleanup steps
    stop_services
    remove_containers
    cleanup_volumes
    cleanup_images
    cleanup_local_files
    check_remaining_resources
    show_cleanup_summary
}

# Handle command line arguments
case "${1:-}" in
    "force")
        force_cleanup
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [OPTION]"
        echo ""
        echo "Options:"
        echo "  (no args)  Perform normal cleanup"
        echo "  force      Force cleanup (emergency option)"
        echo "  help       Show this help message"
        echo ""
        echo "Examples:"
        echo "  $0          # Normal cleanup"
        echo "  $0 force    # Force cleanup"
        echo ""
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac
