#!/bin/bash

# Comprehensive cleanup script for Zero-Downtime Deployment Demo

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"
}

# Stop all deployment containers
stop_deployments() {
    log "Stopping all deployment containers..."
    
    # Stop docker-compose services
    (cd docker/rolling && docker-compose down --remove-orphans) || true
    (cd docker/blue-green && docker-compose down --remove-orphans) || true
    (cd docker/canary && docker-compose down --remove-orphans) || true
    
    log "Deployment containers stopped"
}

# Stop and remove dashboard container
stop_dashboard() {
    log "Stopping dashboard container..."
    
    docker stop zero-downtime-dashboard 2>/dev/null || true
    docker rm zero-downtime-dashboard 2>/dev/null || true
    
    log "Dashboard container stopped and removed"
}

# Stop and remove all containers with zero-downtime prefix
stop_all_containers() {
    log "Stopping all zero-downtime containers..."
    
    # Get all containers with zero-downtime prefix
    containers=$(docker ps -a --filter "name=zero-downtime" --format "{{.Names}}" 2>/dev/null || true)
    
    if [ -n "$containers" ]; then
        echo "$containers" | while read container; do
            if [ -n "$container" ]; then
                warn "Stopping container: $container"
                docker stop "$container" 2>/dev/null || true
                docker rm "$container" 2>/dev/null || true
            fi
        done
    fi
    
    # Also stop containers with rolling, blue-green, canary prefixes
    for prefix in rolling blue-green canary; do
        containers=$(docker ps -a --filter "name=$prefix" --format "{{.Names}}" 2>/dev/null || true)
        if [ -n "$containers" ]; then
            echo "$containers" | while read container; do
                if [ -n "$container" ]; then
                    warn "Stopping container: $container"
                    docker stop "$container" 2>/dev/null || true
                    docker rm "$container" 2>/dev/null || true
                fi
            done
        fi
    done
    
    log "All zero-downtime containers stopped and removed"
}

# Remove all zero-downtime images
remove_images() {
    log "Removing zero-downtime images..."
    
    # Remove specific images
    docker rmi zero-downtime-app-v1 2>/dev/null || true
    docker rmi zero-downtime-app-v2 2>/dev/null || true
    docker rmi zero-downtime-app-v3 2>/dev/null || true
    docker rmi zero-downtime-dashboard 2>/dev/null || true
    
    # Remove any other images with zero-downtime prefix
    images=$(docker images --filter "reference=zero-downtime*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    if [ -n "$images" ]; then
        echo "$images" | while read image; do
            if [ -n "$image" ]; then
                warn "Removing image: $image"
                docker rmi "$image" 2>/dev/null || true
            fi
        done
    fi
    
    log "Zero-downtime images removed"
}

# Clean up networks
cleanup_networks() {
    log "Cleaning up networks..."
    
    # Remove specific networks
    docker network rm rolling_app_network 2>/dev/null || true
    docker network rm blue-green_app_network 2>/dev/null || true
    docker network rm canary_app_network 2>/dev/null || true
    
    # Remove any other networks with app_network suffix
    networks=$(docker network ls --filter "name=app_network" --format "{{.Name}}" 2>/dev/null || true)
    if [ -n "$networks" ]; then
        echo "$networks" | while read network; do
            if [ -n "$network" ]; then
                warn "Removing network: $network"
                docker network rm "$network" 2>/dev/null || true
            fi
        done
    fi
    
    # Prune unused networks
    docker network prune -f
    
    log "Networks cleaned up"
}

# Clean up volumes
cleanup_volumes() {
    log "Cleaning up volumes..."
    
    # Remove volumes with zero-downtime prefix
    volumes=$(docker volume ls --filter "name=zero-downtime" --format "{{.Name}}" 2>/dev/null || true)
    if [ -n "$volumes" ]; then
        echo "$volumes" | while read volume; do
            if [ -n "$volume" ]; then
                warn "Removing volume: $volume"
                docker volume rm "$volume" 2>/dev/null || true
            fi
        done
    fi
    
    # Remove volumes with rolling, blue-green, canary prefixes
    for prefix in rolling blue-green canary; do
        volumes=$(docker volume ls --filter "name=$prefix" --format "{{.Name}}" 2>/dev/null || true)
        if [ -n "$volumes" ]; then
            echo "$volumes" | while read volume; do
                if [ -n "$volume" ]; then
                    warn "Removing volume: $volume"
                    docker volume rm "$volume" 2>/dev/null || true
                fi
            done
        fi
    done
    
    # Prune unused volumes
    docker volume prune -f
    
    log "Volumes cleaned up"
}

# Clean up build cache
cleanup_build_cache() {
    log "Cleaning up build cache..."
    
    # Remove build cache
    docker builder prune -f
    
    log "Build cache cleaned up"
}

# Clean up system
cleanup_system() {
    log "Cleaning up Docker system..."
    
    # Remove unused data
    docker system prune -f
    
    log "Docker system cleaned up"
}

# Show cleanup summary
show_summary() {
    log "Cleanup Summary:"
    
    # Check remaining containers
    remaining_containers=$(docker ps -a --filter "name=zero-downtime" --format "{{.Names}}" 2>/dev/null || true)
    if [ -n "$remaining_containers" ]; then
        warn "Remaining containers:"
        echo "$remaining_containers"
    else
        info "✓ All zero-downtime containers removed"
    fi
    
    # Check remaining images
    remaining_images=$(docker images --filter "reference=zero-downtime*" --format "{{.Repository}}:{{.Tag}}" 2>/dev/null || true)
    if [ -n "$remaining_images" ]; then
        warn "Remaining images:"
        echo "$remaining_images"
    else
        info "✓ All zero-downtime images removed"
    fi
    
    # Check remaining networks
    remaining_networks=$(docker network ls --filter "name=app_network" --format "{{.Name}}" 2>/dev/null || true)
    if [ -n "$remaining_networks" ]; then
        warn "Remaining networks:"
        echo "$remaining_networks"
    else
        info "✓ All zero-downtime networks removed"
    fi
}

# Main cleanup function
cleanup() {
    log "🧹 Starting comprehensive cleanup..."
    
    # Stop all services
    stop_deployments
    stop_dashboard
    stop_all_containers
    
    # Remove resources
    remove_images
    cleanup_networks
    cleanup_volumes
    cleanup_build_cache
    cleanup_system
    
    # Show summary
    show_summary
    
    log "🎉 Cleanup completed successfully!"
}

# Force cleanup (removes everything without confirmation)
force_cleanup() {
    log "💥 Starting force cleanup..."
    
    # Stop and remove ALL containers
    log "Stopping ALL containers..."
    docker stop $(docker ps -aq) 2>/dev/null || true
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    # Remove ALL images
    log "Removing ALL images..."
    docker rmi $(docker images -aq) 2>/dev/null || true
    
    # Remove ALL networks
    log "Removing ALL networks..."
    docker network rm $(docker network ls -q) 2>/dev/null || true
    
    # Remove ALL volumes
    log "Removing ALL volumes..."
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    
    # Clean everything
    docker system prune -af
    
    log "💥 Force cleanup completed! All Docker resources removed."
}

# Main execution
case "${1:-cleanup}" in
    "cleanup")
        cleanup
        ;;
    "force")
        warn "⚠️  This will remove ALL Docker resources (not just zero-downtime ones)"
        read -p "Are you sure? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            force_cleanup
        else
            log "Force cleanup cancelled"
        fi
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 {cleanup|force|help}"
        echo "  cleanup - Clean up zero-downtime demo resources (default)"
        echo "  force   - Remove ALL Docker resources (use with caution!)"
        echo "  help    - Show this help message"
        ;;
    *)
        error "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac