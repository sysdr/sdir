#!/bin/bash

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[DEMO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Docker is running
check_docker() {
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running. Please start Docker Desktop and try again."
        exit 1
    fi
    print_status "Docker is running"
}

# Function to check and kill processes using required ports
check_and_kill_ports() {
    print_status "Checking for processes using required ports..."
    
    docker-compose down 
    
    local ports=(6379)
    local killed_processes=false
    
    for port in "${ports[@]}"; do
        if lsof -ti:$port > /dev/null 2>&1; then
            print_warning "Port $port is in use. Killing process..."
            lsof -ti:$port | xargs kill -9
            killed_processes=true
            sleep 1
        fi
    done
    
    if [ "$killed_processes" = true ]; then
        print_status "Killed processes using required ports. Waiting 3 seconds for cleanup..."
        sleep 3
    else
        print_status "All required ports are available"
    fi
}

# Function to clean up existing Docker containers
cleanup_docker_containers() {
    print_status "Cleaning up existing Docker containers..."
    
    # Stop and remove containers from this project
    docker-compose down --remove-orphans 2>/dev/null || true
    
    # Remove any containers using our ports
    for port in 80 8080 8081 9090 3000 6379; do
        local container_ids=$(docker ps -q --filter "publish=$port")
        if [ ! -z "$container_ids" ]; then
            print_warning "Found Docker containers using port $port. Stopping them..."
            echo "$container_ids" | xargs docker stop 2>/dev/null || true
            echo "$container_ids" | xargs docker rm 2>/dev/null || true
        fi
    done
    
    print_status "Docker cleanup completed"
}

# Function to check if services are ready
wait_for_services() {
    print_status "Waiting for services to be ready..."
    
    # Wait for WebSocket servers
    for port in 8080 8081; do
        while ! curl -s http://localhost:$port/health > /dev/null; do
            echo "Waiting for WebSocket server on port $port..."
            sleep 2
        done
    done
    
    # Wait for Nginx
    while ! curl -s http://localhost:80 > /dev/null; do
        echo "Waiting for Nginx..."
        sleep 2
    done
    
    print_status "All services are ready!"
}

# Function to run load test
run_load_test() {
    print_header "Running Load Test"
    
    cd tests && npm run load-test
    cd ..
}

# Function to run integration tests
run_integration_tests() {
    print_header "Running Integration Tests"
    
    cd tests && npm run test
    cd ..
}

# Function to show metrics
show_metrics() {
    print_header "Server Metrics"
    
    echo "WebSocket Server 1 Metrics:"
    curl -s http://localhost:8080/metrics | jq '.'
    
    echo -e "\nWebSocket Server 2 Metrics:"
    curl -s http://localhost:8081/metrics | jq '.'
}

# Main execution
case "${1:-demo}" in
    "build")
        print_header "Building WebSocket Scaling Demo"
        check_docker
        docker-compose build
        ;;
    
    "start")
        print_header "Starting WebSocket Scaling Demo"
        check_docker
        check_and_kill_ports
        cleanup_docker_containers
        docker-compose up -d
        wait_for_services
        
        echo ""
        echo "🚀 WebSocket Scaling Demo is ready!"
        echo "=================================="
        echo "📱 Web Interface: http://localhost"
        echo "📊 Prometheus: http://localhost:9090"
        echo "📈 Grafana: http://localhost:3000 (admin/admin)"
        echo "🔧 Server 1 API: http://localhost:8080"
        echo "🔧 Server 2 API: http://localhost:8081"
        echo ""
        echo "🧪 Run tests:"
        echo "  ./demo.sh test"
        echo "  ./demo.sh load-test"
        echo ""
        echo "📊 View metrics:"
        echo "  ./demo.sh metrics"
        ;;
    
    "stop")
        print_header "Stopping WebSocket Scaling Demo"
        docker-compose down
        ;;
    
    "clean")
        print_header "Cleaning WebSocket Scaling Demo"
        docker-compose down -v
        docker system prune -f
        ;;
    
    "test")
        run_integration_tests
        ;;
    
    "load-test")
        run_load_test
        ;;
    
    "metrics")
        show_metrics
        ;;
    
    "logs")
        service=${2:-websocket-server-1}
        print_header "Showing logs for $service"
        docker-compose logs -f $service
        ;;
    
    "demo"|*)
        print_header "WebSocket Scaling Demo - Complete Setup"
        
        # Check Docker and ports before starting
        check_docker
        check_and_kill_ports
        cleanup_docker_containers
        
        # Build and start
        ./demo.sh build
        ./demo.sh start
        
        # Run tests
        sleep 5
        ./demo.sh test
        
        # Show final status
        echo ""
        print_status "Demo is running successfully!"
        print_status "Open http://localhost in your browser to interact with the demo"
        ;;
esac