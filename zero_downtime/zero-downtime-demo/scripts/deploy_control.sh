#!/bin/bash

# Deployment control script

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"
}

# Start specific deployment
start_deployment() {
    local strategy=$1
    
    log "Starting $strategy deployment..."
    
    case $strategy in
        "rolling")
            cd docker/rolling && docker-compose up -d && cd ../..
            ;;
        "blue-green")
            cd docker/blue-green && docker-compose up -d && cd ../..
            ;;
        "canary")
            cd docker/canary && docker-compose up -d && cd ../..
            ;;
        *)
            error "Unknown strategy: $strategy"
            exit 1
            ;;
    esac
    
    log "$strategy deployment started"
}

# Stop specific deployment
stop_deployment() {
    local strategy=$1
    
    log "Stopping $strategy deployment..."
    
    case $strategy in
        "rolling")
            cd docker/rolling && docker-compose down && cd ../..
            ;;
        "blue-green")
            cd docker/blue-green && docker-compose down && cd ../..
            ;;
        "canary")
            cd docker/canary && docker-compose down && cd ../..
            ;;
        *)
            error "Unknown strategy: $strategy"
            exit 1
            ;;
    esac
    
    log "$strategy deployment stopped"
}

# Show status
show_status() {
    log "Deployment Status:"
    echo
    
    echo "Rolling (Port 8080):"
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "  Status: Running ✅"
        version=$(curl -s http://localhost:8080/api/info | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "  Version: $version"
    else
        echo "  Status: Stopped ❌"
    fi
    
    echo "Blue-Green (Port 8081):"
    if curl -s http://localhost:8081/health > /dev/null 2>&1; then
        echo "  Status: Running ✅"
        version=$(curl -s http://localhost:8081/api/info | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "  Version: $version"
    else
        echo "  Status: Stopped ❌"
    fi
    
    echo "Canary (Port 8082):"
    if curl -s http://localhost:8082/health > /dev/null 2>&1; then
        echo "  Status: Running ✅"
        version=$(curl -s http://localhost:8082/api/info | grep -o '"version":"[^"]*"' | cut -d'"' -f4 || echo "unknown")
        echo "  Version: $version"
    else
        echo "  Status: Stopped ❌"
    fi
    
    echo "Dashboard (Port 3000):"
    if curl -s http://localhost:3000 > /dev/null 2>&1; then
        echo "  Status: Running ✅"
    else
        echo "  Status: Stopped ❌"
    fi
}

# Main execution
case "${1:-status}" in
    "start")
        if [ -z "$2" ]; then
            echo "Usage: $0 start {rolling|blue-green|canary|all}"
            exit 1
        fi
        if [ "$2" = "all" ]; then
            start_deployment "rolling"
            start_deployment "blue-green"
            start_deployment "canary"
        else
            start_deployment "$2"
        fi
        ;;
    "stop")
        if [ -z "$2" ]; then
            echo "Usage: $0 stop {rolling|blue-green|canary|all}"
            exit 1
        fi
        if [ "$2" = "all" ]; then
            stop_deployment "rolling"
            stop_deployment "blue-green"
            stop_deployment "canary"
        else
            stop_deployment "$2"
        fi
        ;;
    "status")
        show_status
        ;;
    "restart")
        if [ -z "$2" ]; then
            echo "Usage: $0 restart {rolling|blue-green|canary|all}"
            exit 1
        fi
        if [ "$2" = "all" ]; then
            stop_deployment "rolling"
            stop_deployment "blue-green"
            stop_deployment "canary"
            sleep 3
            start_deployment "rolling"
            start_deployment "blue-green"
            start_deployment "canary"
        else
            stop_deployment "$2"
            sleep 2
            start_deployment "$2"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status} [strategy]"
        echo "Strategies: rolling, blue-green, canary, all"
        ;;
esac
