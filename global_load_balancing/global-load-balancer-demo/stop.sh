#!/bin/bash

# Global Load Balancer Demo - Stop Script
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
        print_error "Docker is not running."
        exit 1
    fi
}

# Function to check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose > /dev/null 2>&1; then
        print_error "Docker Compose is not installed."
        exit 1
    fi
}

# Function to check if services are running
check_services_running() {
    if ! docker-compose ps --services --filter "status=running" | grep -q .; then
        print_warning "No services are currently running."
        return 1
    fi
    return 0
}

# Function to stop services gracefully
stop_services() {
    print_status "Stopping services gracefully..."
    
    # Stop services with a timeout
    docker-compose down --timeout 30
    
    print_success "Services stopped successfully"
}

# Function to force stop services if needed
force_stop_services() {
    print_warning "Force stopping services..."
    
    # Kill all containers
    docker-compose kill
    
    # Remove containers
    docker-compose down --remove-orphans
    
    print_success "Services force stopped"
}

# Function to clean up resources
cleanup_resources() {
    print_status "Cleaning up resources..."
    
    # Remove stopped containers
    docker container prune -f > /dev/null 2>&1 || true
    
    # Remove unused networks
    docker network prune -f > /dev/null 2>&1 || true
    
    # Remove unused volumes (be careful with this in production)
    # docker volume prune -f > /dev/null 2>&1 || true
    
    print_success "Resources cleaned up"
}

# Function to show final status
show_final_status() {
    print_status "Final Status:"
    docker-compose ps
    
    echo ""
    print_success "Global Load Balancer Demo has been stopped!"
    echo ""
    echo -e "${GREEN}To restart the services:${NC}"
    echo -e "  • ${BLUE}./start.sh${NC} - Start all services"
    echo -e "  • ${BLUE}./restart.sh${NC} - Restart all services"
    echo ""
    echo -e "${GREEN}To clean up completely:${NC}"
    echo -e "  • ${BLUE}docker-compose down --volumes --remove-orphans${NC} - Remove volumes and orphaned containers"
    echo -e "  • ${BLUE}docker system prune -a${NC} - Remove all unused Docker resources (use with caution)"
}

# Function to handle cleanup on script exit
cleanup() {
    print_status "Cleanup completed"
}

# Set up trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Global Load Balancer Demo${NC}"
    echo -e "${BLUE}  Stopping Services...${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Check prerequisites
    check_docker
    check_docker_compose
    
    # Check if services are running
    if ! check_services_running; then
        show_final_status
        exit 0
    fi
    
    # Show current status
    print_status "Current service status:"
    docker-compose ps
    echo ""
    
    # Stop services
    if ! stop_services; then
        print_warning "Graceful stop failed, attempting force stop..."
        force_stop_services
    fi
    
    # Clean up resources
    cleanup_resources
    
    # Show final status
    show_final_status
}

# Run main function
main "$@" 