#!/bin/bash

# Main demo runner script

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"
}

# Build all Docker images
build_images() {
    log "Building Docker images..."
    
    docker build -t zero-downtime-app-v1 app/v1/
    docker build -t zero-downtime-app-v2 app/v2/
    docker build -t zero-downtime-app-v3 app/v3/
    docker build -t zero-downtime-dashboard dashboard/
    
    log "Docker images built successfully"
}

# Start dashboard
start_dashboard() {
    log "Starting monitoring dashboard..."
    
    # Stop existing dashboard if running
    docker stop zero-downtime-dashboard 2>/dev/null || true
    docker rm zero-downtime-dashboard 2>/dev/null || true
    
    # Start dashboard with proper port mapping and network connections
    docker run -d \
        --name zero-downtime-dashboard \
        -p 3000:3000 \
        --network rolling_app_network \
        --network blue-green_app_network \
        --network canary_app_network \
        zero-downtime-dashboard
    
    log "Dashboard starting on http://localhost:3000"
}

# Start all deployments
start_all() {
    log "Starting all deployment strategies..."
    
    # Rolling deployment
    (cd docker/rolling && docker-compose up -d)
    
    # Blue-Green deployment
    (cd docker/blue-green && docker-compose up -d)
    
    # Canary deployment
    (cd docker/canary && docker-compose up -d)
    
    log "All deployments started"
}

# Stop all deployments
stop_all() {
    log "Stopping all deployments..."
    
    (cd docker/rolling && docker-compose down) || true
    (cd docker/blue-green && docker-compose down) || true
    (cd docker/canary && docker-compose down) || true
    
    docker stop zero-downtime-dashboard 2>/dev/null || true
    docker rm zero-downtime-dashboard 2>/dev/null || true
    
    log "All deployments stopped"
}

# Clean up everything
cleanup() {
    log "Cleaning up Docker resources..."
    
    stop_all
    
    # Remove images
    docker rmi zero-downtime-app-v1 2>/dev/null || true
    docker rmi zero-downtime-app-v2 2>/dev/null || true
    docker rmi zero-downtime-app-v3 2>/dev/null || true
    docker rmi zero-downtime-dashboard 2>/dev/null || true
    
    # Clean up networks
    docker network prune -f
    
    log "Cleanup completed"
}

# Show access information
show_info() {
    info "=== Zero-Downtime Deployment Demo ==="
    echo
    info "🎯 Access Points:"
    echo "  📊 Dashboard:        http://localhost:3000"
    echo "  🔄 Rolling:          http://localhost:8080"
    echo "  🔀 Blue-Green:       http://localhost:8081"
    echo "  🐦 Canary:           http://localhost:8082"
    echo
    info "🧪 Testing:"
    echo "  ./scripts/test_deployments.sh all"
    echo "  ./scripts/deploy_control.sh status"
    echo
    info "📝 Logs:"
    echo "  docker-compose logs -f (in respective directories)"
    echo
    warn "💡 Tip: Visit the dashboard to monitor deployments interactively!"
    echo
    info "📚 Learning Objectives:"
    echo "  • Understand traffic switching mechanisms"
    echo "  • Compare resource usage across strategies"  
    echo "  • Experience zero-downtime deployment patterns"
    echo "  • Practice failure scenario handling"
}

# Wait for services to be ready
wait_for_services() {
    log "Waiting for services to be ready..."
    
    local max_attempts=60
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        local ready_count=0
        
        if curl -s http://localhost:8080/health > /dev/null 2>&1; then
            ready_count=$((ready_count + 1))
        fi
        
        if curl -s http://localhost:8081/health > /dev/null 2>&1; then
            ready_count=$((ready_count + 1))
        fi
        
        if curl -s http://localhost:8082/health > /dev/null 2>&1; then
            ready_count=$((ready_count + 1))
        fi
        
        if [ $ready_count -eq 3 ]; then
            log "All services are ready!"
            return 0
        fi
        
        attempt=$((attempt + 1))
        echo -n "."
        sleep 2
    done
    
    warn "Some services may not be ready yet. Check status with: ./scripts/deploy_control.sh status"
}

# Main execution
case "${1:-start}" in
    "build")
        build_images
        ;;
    "start")
        build_images
        start_all
        start_dashboard
        wait_for_services
        show_info
        ;;
    "stop")
        stop_all
        ;;
    "restart")
        stop_all
        sleep 3
        build_images
        start_all
        start_dashboard
        wait_for_services
        show_info
        ;;
    "clean")
        cleanup
        ;;
    "info")
        show_info
        ;;
    "test")
        ./scripts/test_deployments.sh all
        ;;
    *)
        echo "Usage: $0 {build|start|stop|restart|clean|info|test}"
        echo "  build   - Build Docker images"
        echo "  start   - Start all services"
        echo "  stop    - Stop all services"
        echo "  restart - Restart all services"
        echo "  clean   - Clean up all Docker resources"
        echo "  info    - Show access information"
        echo "  test    - Run deployment tests"
        ;;
esac
