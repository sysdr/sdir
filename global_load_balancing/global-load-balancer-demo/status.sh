#!/bin/bash

# Global Load Balancer Demo - Status Script
# System Design Interview Roadmap - Issue #99

set -e

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

# Function to check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running."
        return 1
    fi
    return 0
}

# Function to check if Docker Compose is available
check_docker_compose() {
    if ! command -v docker-compose > /dev/null 2>&1; then
        print_error "Docker Compose is not installed."
        return 1
    fi
    return 0
}

# Function to show Docker system info
show_docker_info() {
    print_header "Docker System Information"
    echo "Docker Version: $(docker --version)"
    echo "Docker Compose Version: $(docker-compose --version)"
    echo "Docker Status: $(docker info --format '{{.ServerVersion}}')"
    echo ""
}

# Function to show service status
show_service_status() {
    print_header "Service Status"
    
    if ! docker-compose ps --services --filter "status=running" | grep -q .; then
        print_warning "No services are currently running."
        echo ""
        print_status "To start services: ./start.sh"
        return
    fi
    
    docker-compose ps
    echo ""
}

# Function to show resource usage
show_resource_usage() {
    print_header "Resource Usage"
    
    if ! docker-compose ps --services --filter "status=running" | grep -q .; then
        print_warning "No services running to show resource usage."
        return
    fi
    
    echo "Container Resource Usage:"
    docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
    echo ""
}

# Function to show network information
show_network_info() {
    print_header "Network Information"
    
    echo "Docker Networks:"
    docker network ls --filter "name=global-load-balancer-demo" --format "table {{.ID}}\t{{.Name}}\t{{.Driver}}\t{{.Scope}}"
    echo ""
    
    echo "Port Mappings:"
    echo "  • Application: http://localhost:5000"
    echo "  • Nginx Proxy: http://localhost:8888"
    echo ""
}

# Function to show health check status
show_health_status() {
    print_header "Health Check Status"
    
    if ! docker-compose ps --services --filter "status=running" | grep -q .; then
        print_warning "No services running to check health."
        return
    fi
    
    # Check application health
    if curl -s http://localhost:5000/health > /dev/null 2>&1; then
        print_success "Application health check: OK"
    else
        print_error "Application health check: FAILED"
    fi
    
    # Check nginx health
    if curl -s http://localhost:8888 > /dev/null 2>&1; then
        print_success "Nginx proxy health check: OK"
    else
        print_error "Nginx proxy health check: FAILED"
    fi
    
    echo ""
}

# Function to show recent logs
show_recent_logs() {
    print_header "Recent Logs (Last 10 lines)"
    
    if ! docker-compose ps --services --filter "status=running" | grep -q .; then
        print_warning "No services running to show logs."
        return
    fi
    
    docker-compose logs --tail=10
    echo ""
}

# Function to show API endpoints
show_api_endpoints() {
    print_header "Available API Endpoints"
    
    if ! docker-compose ps --services --filter "status=running" | grep -q .; then
        print_warning "No services running to show API endpoints."
        return
    fi
    
    echo "Application API:"
    echo "  • Health Check:     http://localhost:5000/health"
    echo "  • Data Centers:     http://localhost:5000/api/data-centers"
    echo "  • Statistics:       http://localhost:5000/api/stats"
    echo "  • Request Handler:  http://localhost:5000/api/request (POST)"
    echo "  • Configuration:    http://localhost:5000/api/config (POST)"
    echo ""
    echo "Nginx Proxy:"
    echo "  • Main Application: http://localhost:8888"
    echo ""
}

# Function to show management commands
show_management_commands() {
    print_header "Management Commands"
    
    echo "Service Management:"
    echo "  • Start services:   ./start.sh"
    echo "  • Stop services:    ./stop.sh"
    echo "  • Restart services: ./restart.sh"
    echo "  • Check status:     ./status.sh"
    echo ""
    echo "Docker Commands:"
    echo "  • View logs:        docker-compose logs -f"
    echo "  • View logs (app):  docker-compose logs -f global-lb"
    echo "  • View logs (nginx): docker-compose logs -f nginx"
    echo "  • Shell into app:   docker-compose exec global-lb bash"
    echo "  • Shell into nginx: docker-compose exec nginx sh"
    echo ""
    echo "Cleanup Commands:"
    echo "  • Stop & remove:    docker-compose down"
    echo "  • Remove volumes:   docker-compose down --volumes"
    echo "  • Remove all:       docker-compose down --volumes --remove-orphans"
    echo ""
}

# Function to show system information
show_system_info() {
    print_header "System Information"
    
    echo "Operating System: $(uname -s) $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Current Directory: $(pwd)"
    echo "Available Disk Space: $(df -h . | tail -1 | awk '{print $4}')"
    echo "Available Memory: $(free -h | grep Mem | awk '{print $7}')"
    echo ""
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Global Load Balancer Demo${NC}"
    echo -e "${BLUE}  Service Status Report${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Check prerequisites
    if ! check_docker; then
        exit 1
    fi
    
    if ! check_docker_compose; then
        exit 1
    fi
    
    # Show all information
    show_system_info
    show_docker_info
    show_service_status
    show_resource_usage
    show_network_info
    show_health_status
    show_api_endpoints
    show_recent_logs
    show_management_commands
    
    print_success "Status check completed!"
}

# Run main function
main "$@" 