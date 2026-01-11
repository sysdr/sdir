#!/bin/bash

set -e

echo "=========================================="
echo "Feature Flag System - Complete Cleanup"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Stop all running containers
echo "Step 1: Stopping all Docker containers..."
if [ -f "flag-system/docker-compose.yml" ]; then
    cd flag-system
    docker-compose down -v 2>/dev/null || true
    cd ..
    print_info "Stopped containers from flag-system/docker-compose.yml"
fi

if [ -f "docker-compose.yml" ]; then
    docker-compose down -v 2>/dev/null || true
    print_info "Stopped containers from root docker-compose.yml"
fi

# Stop any remaining containers
STOPPED=$(docker ps -aq | xargs -r docker stop 2>/dev/null || echo "")
if [ -n "$STOPPED" ]; then
    print_info "Stopped additional running containers"
fi

# Remove all stopped containers
echo ""
echo "Step 2: Removing stopped containers..."
REMOVED=$(docker ps -aq | xargs -r docker rm 2>/dev/null || echo "")
if [ -n "$REMOVED" ]; then
    print_info "Removed stopped containers"
else
    print_warn "No stopped containers to remove"
fi

# Remove unused Docker images
echo ""
echo "Step 3: Removing unused Docker images..."
docker image prune -af --filter "label!=keep" 2>/dev/null || true
print_info "Removed unused Docker images"

# Remove unused Docker volumes
echo ""
echo "Step 4: Removing unused Docker volumes..."
docker volume prune -af 2>/dev/null || true
print_info "Removed unused Docker volumes"

# Remove unused Docker networks
echo ""
echo "Step 5: Removing unused Docker networks..."
docker network prune -af 2>/dev/null || true
print_info "Removed unused Docker networks"

# Remove build cache (optional - commented out as it's more aggressive)
# echo ""
# echo "Step 6: Removing Docker build cache..."
# docker builder prune -af 2>/dev/null || true
# print_info "Removed Docker build cache"

# Clean up project-specific files
echo ""
echo "Step 6: Cleaning up project files..."
FOUND_FILES=0

# Remove node_modules directories
if find . -type d -name "node_modules" -prune -exec rm -rf {} + 2>/dev/null; then
    FOUND_FILES=1
fi

# Remove venv directories
if find . -type d -name "venv" -prune -exec rm -rf {} + 2>/dev/null; then
    FOUND_FILES=1
fi

# Remove .pytest_cache directories
if find . -type d -name ".pytest_cache" -prune -exec rm -rf {} + 2>/dev/null; then
    FOUND_FILES=1
fi

# Remove __pycache__ directories
if find . -type d -name "__pycache__" -prune -exec rm -rf {} + 2>/dev/null; then
    FOUND_FILES=1
fi

# Remove .pyc files
if find . -type f -name "*.pyc" -delete 2>/dev/null; then
    FOUND_FILES=1
fi

# Remove .pyo files
if find . -type f -name "*.pyo" -delete 2>/dev/null; then
    FOUND_FILES=1
fi

# Remove Istio-related files
if find . -name "*istio*" -o -name "*Istio*" 2>/dev/null | xargs -r rm -rf; then
    FOUND_FILES=1
fi

if [ $FOUND_FILES -eq 1 ]; then
    print_info "Removed node_modules, venv, .pytest_cache, .pyc files, and Istio files"
else
    print_warn "No project files to clean (node_modules, venv, etc. not found)"
fi

# Summary
echo ""
echo "=========================================="
echo "Cleanup Summary"
echo "=========================================="
echo ""
echo "Containers:"
docker ps -a --format "  {{.Names}} - {{.Status}}" 2>/dev/null || echo "  No containers"
echo ""
echo "Docker Images (relevant to this project):"
docker images --format "  {{.Repository}}:{{.Tag}} - {{.Size}}" | grep -i flag || echo "  No flag-related images"
echo ""
echo "Docker Volumes:"
docker volume ls --format "  {{.Name}}" | grep -i flag || echo "  No flag-related volumes"
echo ""

print_info "Cleanup complete!"
echo ""
echo "Note: To remove Docker build cache (more aggressive cleanup),"
echo "      run: docker builder prune -af"
echo ""

