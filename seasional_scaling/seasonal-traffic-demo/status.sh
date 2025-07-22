#!/bin/bash

# Seasonal Traffic Demo - Status Script
# This script checks the status of all services and provides useful information

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

# Function to check service status
check_service_status() {
    print_header "=== Service Status ==="
    
    if ! docker-compose ps > /dev/null 2>&1; then
        print_warning "No docker-compose services found."
        return 1
    fi
    
    echo
    docker-compose ps
    echo
}

# Function to check service health
check_service_health() {
    print_header "=== Health Checks ==="
    
    # Check scaling demo health
    if curl -f http://localhost:8000/api/metrics > /dev/null 2>&1; then
        print_success "Scaling Demo (port 8000): Healthy"
    else
        print_error "Scaling Demo (port 8000): Unhealthy or not responding"
    fi
    
    # Check Prometheus health
    if curl -f http://localhost:9090/-/healthy > /dev/null 2>&1; then
        print_success "Prometheus (port 9090): Healthy"
    else
        print_error "Prometheus (port 9090): Unhealthy or not responding"
    fi
    
    echo
}

# Function to show service endpoints
show_endpoints() {
    print_header "=== Available Endpoints ==="
    echo
    echo -e "${GREEN}Scaling Demo:${NC}"
    echo -e "  • Main Demo:    ${BLUE}http://localhost:8000${NC}"
    echo -e "  • API Metrics:  ${BLUE}http://localhost:8000/api/metrics${NC}"
    echo -e "  • WebSocket:    ${BLUE}ws://localhost:8000/ws${NC}"
    echo
    echo -e "${GREEN}Prometheus:${NC}"
    echo -e "  • Dashboard:    ${BLUE}http://localhost:9090${NC}"
    echo -e "  • Targets:      ${BLUE}http://localhost:9090/targets${NC}"
    echo -e "  • Graph:        ${BLUE}http://localhost:9090/graph${NC}"
    echo
}

# Function to show resource usage
show_resource_usage() {
    print_header "=== Resource Usage ==="
    
    if docker-compose ps | grep -q "Up"; then
        echo
        docker stats --no-stream --format "table {{.Container}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}\t{{.BlockIO}}"
        echo
    else
        print_warning "No running containers to show resource usage."
        echo
    fi
}

# Function to show recent logs
show_recent_logs() {
    print_header "=== Recent Logs ==="
    
    if docker-compose ps | grep -q "Up"; then
        echo
        docker-compose logs --tail=15
        echo
    else
        print_warning "No running services to show logs."
        echo
    fi
}

# Function to show system information
show_system_info() {
    print_header "=== System Information ==="
    echo
    echo -e "${GREEN}Docker Version:${NC} $(docker --version)"
    echo -e "${GREEN}Docker Compose Version:${NC} $(docker-compose --version)"
    echo -e "${GREEN}Available Memory:${NC} $(free -h | grep Mem | awk '{print $2}')"
    echo -e "${GREEN}Available Disk Space:${NC} $(df -h . | tail -1 | awk '{print $4}')"
    echo
}

# Function to show quick actions
show_quick_actions() {
    print_header "=== Quick Actions ==="
    echo
    echo -e "${GREEN}Start Services:${NC}    ${BLUE}./start.sh${NC}"
    echo -e "${GREEN}Stop Services:${NC}     ${BLUE}./stop.sh${NC}"
    echo -e "${GREEN}View Logs:${NC}         ${BLUE}docker-compose logs -f${NC}"
    echo -e "${GREEN}Restart Services:${NC}  ${BLUE}docker-compose restart${NC}"
    echo -e "${GREEN}Rebuild Services:${NC}  ${BLUE}docker-compose up -d --build${NC}"
    echo
}

# Function to check for issues
check_for_issues() {
    print_header "=== Issue Detection ==="
    
    local issues_found=false
    
    # Check if ports are in use by other processes
    if lsof -i :8000 > /dev/null 2>&1; then
        local port_8000_process=$(lsof -i :8000 | grep LISTEN | head -1 | awk '{print $1}')
        if [ -n "$port_8000_process" ] && [ "$port_8000_process" != "docker" ]; then
            print_warning "Port 8000 is in use by: $port_8000_process"
            issues_found=true
        fi
    fi
    
    if lsof -i :9090 > /dev/null 2>&1; then
        local port_9090_process=$(lsof -i :9090 | grep LISTEN | head -1 | awk '{print $1}')
        if [ -n "$port_9090_process" ] && [ "$port_9090_process" != "docker" ]; then
            print_warning "Port 9090 is in use by: $port_9090_process"
            issues_found=true
        fi
    fi
    
    # Check Docker disk space
    local docker_disk_usage=$(docker system df | grep "Total Space" | awk '{print $3}' | sed 's/%//')
    if [ -n "$docker_disk_usage" ] && [ "$docker_disk_usage" -gt 80 ]; then
        print_warning "Docker disk usage is high: ${docker_disk_usage}%"
        issues_found=true
    fi
    
    if [ "$issues_found" = false ]; then
        print_success "No obvious issues detected."
    fi
    
    echo
}

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Seasonal Traffic Demo - Status${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    
    # Check Docker
    if ! check_docker; then
        exit 1
    fi
    
    # Show system information
    show_system_info
    
    # Check service status
    check_service_status
    
    # Check for issues
    check_for_issues
    
    # Check service health
    check_service_health
    
    # Show endpoints
    show_endpoints
    
    # Show resource usage
    show_resource_usage
    
    # Show recent logs
    show_recent_logs
    
    # Show quick actions
    show_quick_actions
    
    print_success "Status check completed!"
}

# Handle command line arguments
case "${1:-}" in
    --logs|-l)
        print_header "=== Service Logs ==="
        docker-compose logs -f
        ;;
    --resources|-r)
        print_header "=== Resource Usage ==="
        docker stats --no-stream
        ;;
    --health|-h)
        check_service_health
        ;;
    --help)
        echo "Usage: $0 [OPTIONS]"
        echo
        echo "Options:"
        echo "  --logs, -l      Show live logs"
        echo "  --resources, -r Show resource usage"
        echo "  --health, -h    Show health checks only"
        echo "  --help          Show this help message"
        echo
        echo "Examples:"
        echo "  $0              Show full status"
        echo "  $0 --logs       Show live logs"
        echo "  $0 --resources  Show resource usage"
        ;;
    *)
        main "$@"
        ;;
esac 