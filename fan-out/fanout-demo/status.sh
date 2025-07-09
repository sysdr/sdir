#!/bin/bash

# Fanout Demo Status Script
# This script shows the current status of the fanout demo application

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose > /dev/null 2>&1; then
        print_error "Docker Compose is not installed."
        exit 1
    fi
}

# Show container status
show_container_status() {
    print_header "Container Status:"
    echo ""
    
    if docker-compose ps | grep -q "Up"; then
        docker-compose ps
        echo ""
        print_success "Containers are running"
    else
        print_warning "No containers are currently running"
        echo ""
        print_status "To start the application, run: ./start.sh"
    fi
}

# Show service information
show_service_info() {
    print_header "Service Information:"
    echo ""
    echo "  • Web Application: http://localhost:8080"
    echo "  • Redis: localhost:6379"
    echo ""
    
    # Check if application is accessible
    if curl -s http://localhost:8080 > /dev/null 2>&1; then
        print_success "Web application is accessible"
    else
        print_warning "Web application is not accessible"
    fi
    
    # Check Redis connection
    if docker-compose ps | grep -q "redis.*Up"; then
        print_success "Redis service is running"
    else
        print_warning "Redis service is not running"
    fi
}

# Show resource usage
show_resource_usage() {
    print_header "Resource Usage:"
    echo ""
    
    if docker-compose ps | grep -q "Up"; then
        echo "Container resource usage:"
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}" $(docker-compose ps -q)
    else
        print_warning "No running containers to show resource usage"
    fi
}

# Show logs (last 10 lines)
show_recent_logs() {
    print_header "Recent Logs (last 10 lines):"
    echo ""
    
    if docker-compose ps | grep -q "Up"; then
        docker-compose logs --tail=10
    else
        print_warning "No running containers to show logs"
    fi
}

# Show available commands
show_available_commands() {
    print_header "Available Commands:"
    echo ""
    echo "  • Start application: ./start.sh"
    echo "  • Stop application: ./stop.sh"
    echo "  • Restart application: ./restart.sh"
    echo "  • View logs: docker-compose logs -f"
    echo "  • View status: ./status.sh"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Fanout Demo Status Script${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Check Docker Compose
    check_docker_compose
    
    # Show container status
    show_container_status
    
    # Show service information
    show_service_info
    
    # Show resource usage
    show_resource_usage
    
    # Show recent logs
    show_recent_logs
    
    # Show available commands
    show_available_commands
}

# Run main function
main "$@" 