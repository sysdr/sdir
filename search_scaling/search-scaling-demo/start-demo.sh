#!/bin/bash

# Search Scaling Demo - Start Script
# This script starts the demo environment and provides status monitoring

set -e  # Exit on any error

echo "🚀 Starting Search Scaling Demo"
echo "==============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

print_demo() {
    echo -e "${PURPLE}[DEMO]${NC} $1"
}

# Check if build was completed
check_build() {
    print_status "Checking if build was completed..."
    
    if [ ! -f ".build_completed" ]; then
        print_warning "Build completion marker not found. Running build first..."
        ./build.sh
        touch .build_completed
    fi
    
    print_success "Build verification completed"
}

# Start the services
start_services() {
    print_status "Starting all services with Docker Compose..."
    
    # Start services in detached mode
    docker-compose up -d
    
    print_success "Services started successfully"
}

# Wait for services to be healthy
wait_for_services() {
    print_status "Waiting for all services to be healthy..."
    
    services=("elasticsearch" "redis" "postgres" "search-app")
    max_wait=120  # Maximum wait time in seconds
    wait_time=0
    
    while [ $wait_time -lt $max_wait ]; do
        all_healthy=true
        
        for service in "${services[@]}"; do
            if ! docker-compose ps $service | grep -q "healthy\|Up"; then
                all_healthy=false
                break
            fi
        done
        
        if [ "$all_healthy" = true ]; then
            print_success "All services are healthy!"
            return 0
        fi
        
        print_status "Waiting for services to be ready... ($wait_time/$max_wait seconds)"
        sleep 5
        wait_time=$((wait_time + 5))
    done
    
    print_error "Timeout waiting for services to be healthy"
    return 1
}

# Check application health
check_app_health() {
    print_status "Checking application health..."
    
    max_retries=30
    retry_count=0
    
    while [ $retry_count -lt $max_retries ]; do
        if curl -s http://localhost:5000/health > /dev/null 2>&1; then
            print_success "Application is healthy and responding"
            return 0
        fi
        
        print_status "Waiting for application to be ready... ($retry_count/$max_retries)"
        sleep 2
        retry_count=$((retry_count + 1))
    done
    
    print_error "Application health check failed"
    return 1
}

# Display service status
show_status() {
    print_status "Current service status:"
    echo ""
    docker-compose ps
    echo ""
}

# Display demo information
show_demo_info() {
    print_demo "🎉 Demo is now running!"
    echo ""
    echo "📊 Demo Features:"
    echo "   • PostgreSQL full-text search"
    echo "   • Elasticsearch search with highlighting"
    echo "   • Redis caching for improved performance"
    echo "   • Real-time performance metrics"
    echo "   • Search comparison tools"
    echo ""
    echo "🌐 Access Points:"
    echo "   • Web Interface: http://localhost:5000"
    echo "   • Elasticsearch: http://localhost:9200"
    echo "   • Redis: localhost:6379"
    echo "   • PostgreSQL: localhost:5432"
    echo ""
    echo "🔧 Management Commands:"
    echo "   • View logs: docker-compose logs -f"
    echo "   • Stop demo: ./cleanup.sh"
    echo "   • Simulate load: ./simulate-load.sh"
    echo "   • Monitor metrics: curl http://localhost:5000/metrics"
    echo ""
}

# Monitor logs in background
start_log_monitor() {
    print_status "Starting log monitor (press Ctrl+C to stop monitoring)..."
    echo ""
    
    # Start log monitoring in background
    docker-compose logs -f --tail=50 &
    LOG_PID=$!
    
    # Function to cleanup on exit
    cleanup() {
        print_status "Stopping log monitor..."
        kill $LOG_PID 2>/dev/null || true
        exit 0
    }
    
    # Set trap to cleanup on script exit
    trap cleanup SIGINT SIGTERM
    
    # Wait for log process
    wait $LOG_PID
}

# Main start process
main() {
    echo ""
    print_status "Starting demo environment..."
    
    check_build
    start_services
    wait_for_services
    check_app_health
    show_status
    show_demo_info
    
    # Ask user if they want to monitor logs
    echo -n "Would you like to monitor logs? (y/n): "
    read -r monitor_logs
    
    if [[ $monitor_logs =~ ^[Yy]$ ]]; then
        start_log_monitor
    else
        print_status "Demo is running! Open http://localhost:5000 to start exploring."
        print_status "Use './simulate-load.sh' to test performance or './cleanup.sh' to stop."
    fi
}

# Run main function
main "$@" 