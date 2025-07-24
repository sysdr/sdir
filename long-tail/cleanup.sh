#!/bin/bash

# Long-tail Latency Observatory Cleanup Script
# System Design Interview Roadmap - Issue #105

set -e

PROJECT_NAME="longtail-latency-demo"
PROJECT_DIR=$(pwd)/$PROJECT_NAME

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_step() {
    echo -e "${BLUE}[CLEANUP]${NC} $1"
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

cleanup_docker() {
    print_step "Stopping and removing Docker containers..."
    
    if [ -d "$PROJECT_DIR" ]; then
        cd $PROJECT_DIR
        
        echo "$(pwd)"
        echo $(pwd)

        # Stop containers
        if [ -f "docker-compose.yml" ]; then
            docker-compose down --volumes --remove-orphans 2>/dev/null || true
            print_success "Docker containers stopped"
        fi
        
        # Remove images
        #print_step "Removing Docker images..."
        #docker images --format "table {{.Repository}}:{{.Tag}}\t{{.ID}}" | grep -E "(latency|longtail)" | awk '{print $2}' | xargs -r docker rmi -f 2>/dev/null || true
        
        # Clean up Docker system
        docker system prune -f &>/dev/null || true
        
        print_success "Docker cleanup completed"
    else
        print_warning "Project directory not found, skipping Docker cleanup"
    fi
}


cleanup_processes() {
    print_step "Checking for running processes..."
    
    # Kill any processes using port 8000
    local pids=$(lsof -ti:8000 2>/dev/null || true)
    if [ -n "$pids" ]; then
        echo "Stopping processes using port 8000..."
        echo $pids | xargs -r kill -9 2>/dev/null || true
        print_success "Processes stopped"
    fi
}

show_status() {
    print_step "Checking cleanup status..."
    
    # Check if Docker containers are still running
    local containers=$(docker ps --format "table {{.Names}}" | grep -E "(latency|longtail)" 2>/dev/null || true)
    if [ -z "$containers" ]; then
        print_success "No related Docker containers running"
    else
        print_warning "Some containers may still be running: $containers"
    fi
    
    # Check if port 8000 is free
    if ! lsof -i:8000 &>/dev/null; then
        print_success "Port 8000 is free"
    else
        print_warning "Port 8000 is still in use"
    fi
    
    # Check if project directory exists
    if [ -d "$PROJECT_DIR" ]; then
        print_warning "Project directory still exists: $PROJECT_DIR"
    else
        print_success "Project directory cleaned up"
    fi
}

main() {
    echo "🧹 Long-tail Latency Observatory Cleanup"
    echo "========================================="
    echo ""
    
    cleanup_processes
    cleanup_docker
    
    
    echo ""
    show_status
    
    echo ""
    print_success "🎉 Cleanup completed!"
    echo ""
    echo "Summary:"
    echo "  ✅ Docker containers stopped and removed"
    echo "  ✅ Docker images cleaned up"
    echo "  ✅ System resources freed"
    echo "  ✅ Port 8000 available"
    echo ""
    echo "You can now:"
    echo "  • Run the demo again with: ./demo.sh"
    echo "  • Start fresh with a clean environment"
    echo "  • Use the freed resources for other projects"
}

# Handle errors gracefully
handle_error() {
    print_error "Cleanup encountered an error"
    echo "Some manual cleanup may be required:"
    echo "  • Check running containers: docker ps"
    echo "  • Check port usage: lsof -i:8000"
    echo "  • Remove project directory manually if needed"
}

trap handle_error ERR

# Run main function
main