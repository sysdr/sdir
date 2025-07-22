#!/bin/bash

# Seasonal Traffic Demo - Stop Script
# This script stops the entire demo environment and provides cleanup options

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

# Function to check if services are running
check_running_services() {
    if ! docker-compose ps | grep -q "Up"; then
        print_warning "No services are currently running."
        return 1
    fi
    return 0
}

# Function to stop services gracefully
stop_services() {
    print_status "Stopping services gracefully..."
    
    # Stop services with timeout
    timeout 30 docker-compose down --timeout 10
    
    if [ $? -eq 124 ]; then
        print_warning "Services did not stop gracefully within timeout. Force stopping..."
        docker-compose down --timeout 1
    fi
    
    print_success "Services stopped successfully"
}

# Function to force stop services
force_stop_services() {
    print_status "Force stopping services..."
    
    # Kill all containers
    docker-compose kill
    
    # Remove containers
    docker-compose down --remove-orphans
    
    print_success "Services force stopped"
}

# Function to show running services
show_running_services() {
    print_status "Currently running services:"
    echo
    docker-compose ps
    echo
}

# Function to show service logs before stopping
show_logs() {
    print_status "Recent logs from services:"
    echo
    docker-compose logs --tail=20
    echo
}

# Function to cleanup options
cleanup_options() {
    echo
    print_status "Cleanup options:"
    echo -e "  ${GREEN}1.${NC} Remove containers only (default)"
    echo -e "  ${GREEN}2.${NC} Remove containers and images"
    echo -e "  ${GREEN}3.${NC} Remove containers, images, and volumes"
    echo -e "  ${GREEN}4.${NC} Remove containers, images, volumes, and networks"
    echo -e "  ${GREEN}5.${NC} Keep everything (just stop services)"
    echo
    
    read -p "Enter your choice (1-5) [default: 1]: " choice
    choice=${choice:-1}
    
    case $choice in
        1)
            print_status "Removing containers only..."
            docker-compose down
            ;;
        2)
            print_status "Removing containers and images..."
            docker-compose down --rmi all
            ;;
        3)
            print_status "Removing containers, images, and volumes..."
            docker-compose down --rmi all --volumes
            ;;
        4)
            print_status "Removing containers, images, volumes, and networks..."
            docker-compose down --rmi all --volumes --remove-orphans
            ;;
        5)
            print_status "Keeping everything..."
            ;;
        *)
            print_error "Invalid choice. Removing containers only..."
            docker-compose down
            ;;
    esac
}

# Function to show final status
show_final_status() {
    echo
    print_success "🎉 Seasonal Traffic Demo has been stopped!"
    echo
    echo -e "${GREEN}To restart the demo:${NC}"
    echo -e "  • Run: ${BLUE}./start.sh${NC}"
    echo -e "  • Or:  ${BLUE}docker-compose up -d${NC}"
    echo
}

# Function to check for orphaned containers
check_orphans() {
    local orphaned_containers=$(docker ps -a --filter "label=com.docker.compose.project=seasonal-traffic-demo" --format "table {{.Names}}\t{{.Status}}" | grep -v "NAMES")
    
    if [ -n "$orphaned_containers" ]; then
        print_warning "Found orphaned containers:"
        echo "$orphaned_containers"
        echo
        
        read -p "Remove orphaned containers? (y/N): " remove_orphans
        if [[ $remove_orphans =~ ^[Yy]$ ]]; then
            docker-compose down --remove-orphans
            print_success "Orphaned containers removed"
        fi
    fi
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Seasonal Traffic Demo - Stop${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    
    # Check Docker
    check_docker
    
    # Check if services are running
    if ! check_running_services; then
        print_warning "No services to stop."
        show_final_status
        exit 0
    fi
    
    # Show running services
    show_running_services
    
    # Show recent logs
    show_logs
    
    # Ask user for cleanup preference
    cleanup_options
    
    # Check for orphaned containers
    check_orphans
    
    # Show final status
    show_final_status
}

# Handle command line arguments
case "${1:-}" in
    --force|-f)
        echo -e "${BLUE}================================${NC}"
        echo -e "${BLUE}  Seasonal Traffic Demo - Force Stop${NC}"
        echo -e "${BLUE}================================${NC}"
        echo
        
        check_docker
        force_stop_services
        show_final_status
        ;;
    --help|-h)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --force, -f    Force stop services without cleanup prompts"
        echo "  --help, -h     Show this help message"
        echo
        echo "Examples:"
        echo "  $0              Stop services with cleanup options"
        echo "  $0 --force      Force stop services immediately"
        ;;
    *)
        main "$@"
        ;;
esac 