#!/bin/bash

# Cleanup script for disaster recovery demo
# This script stops and removes all containers, networks, and volumes

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[CLEANUP] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[CLEANUP] $1${NC}"
}

error() {
    echo -e "${RED}[CLEANUP] $1${NC}"
}

main() {
    log "Starting cleanup of disaster recovery demo..."
    
    # Stop and remove containers
    log "Stopping all containers..."
    docker-compose down --remove-orphans || warn "Some containers may have already been stopped"
    
    # Remove volumes
    log "Removing volumes..."
    docker-compose down -v || warn "Some volumes may have already been removed"
    
    # Remove networks
    log "Removing networks..."
    docker network rm disaster-recovery-net 2>/dev/null || warn "Network may have already been removed"
    
    # Clean up any dangling containers from this project
    log "Cleaning up any remaining disaster recovery containers..."
    docker ps -a --filter "name=disaster-recovery" --filter "name=payment-service" \
        --filter "name=inventory-service" --filter "name=analytics-service" \
        --filter "name=backup-system" --filter "name=dashboard" \
        --filter "name=disaster-injector" --filter "name=redis-primary" \
        --filter "name=postgres-primary" --filter "name=influxdb" \
        -q | xargs -r docker rm -f || warn "No additional containers to remove"
    
    # Remove any dangling images
    log "Removing unused images..."
    docker image prune -f || warn "No unused images to remove"
    
    # Clean up logs and data directories
    if [ -d "logs" ]; then
        log "Cleaning up log files..."
        rm -rf logs/*
    fi
    
    if [ -d "data" ]; then
        log "Cleaning up data directories..."
        rm -rf data/*
    fi
    
    log "Cleanup completed successfully! 🧹"
    log ""
    log "All disaster recovery demo components have been removed:"
    log "✓ All containers stopped and removed"
    log "✓ All volumes removed"
    log "✓ All networks removed"
    log "✓ Log files cleaned up"
    log "✓ Data directories cleaned up"
    log ""
    log "You can now safely delete the project directory or run the demo again."
}

main "$@"
