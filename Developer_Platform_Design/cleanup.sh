#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "Cleaning Up Developer Platform"
echo "======================================"

# Step 1: Stop all running containers
echo ""
echo "Step 1: Stopping all containers..."
if [ -d "dev-platform" ]; then
    cd dev-platform
    if command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
        docker compose down -v 2>/dev/null || true
    elif command -v docker-compose &> /dev/null; then
        docker-compose down -v 2>/dev/null || true
    fi
    cd ..
fi

# Stop any other running containers
docker ps -q | xargs -r docker stop 2>/dev/null || true

echo "✅ Containers stopped"

# Step 2: Remove stopped containers
echo ""
echo "Step 2: Removing stopped containers..."
docker container prune -f 2>/dev/null || true
echo "✅ Stopped containers removed"

# Step 3: Remove unused images
echo ""
echo "Step 3: Removing unused Docker images..."
docker image prune -a -f 2>/dev/null || true
echo "✅ Unused images removed"

# Step 4: Remove unused volumes
echo ""
echo "Step 4: Removing unused volumes..."
docker volume prune -f 2>/dev/null || true
echo "✅ Unused volumes removed"

# Step 5: Remove unused networks
echo ""
echo "Step 5: Removing unused networks..."
docker network prune -f 2>/dev/null || true
echo "✅ Unused networks removed"

# Step 6: Remove build cache (optional - uncomment if needed)
# echo ""
# echo "Step 6: Removing build cache..."
# docker builder prune -a -f 2>/dev/null || true
# echo "✅ Build cache removed"

# Step 7: Remove project-specific Docker resources
echo ""
echo "Step 7: Removing project-specific resources..."
docker images | grep "dev-platform" | awk '{print $3}' | xargs -r docker rmi -f 2>/dev/null || true
echo "✅ Project-specific images removed"

# Step 8: Clean up generated files (optional - keep dev-platform for now)
# Uncomment the following lines if you want to remove the entire dev-platform directory
# echo ""
# echo "Step 8: Removing generated files..."
# rm -rf dev-platform
# echo "✅ Generated files removed"

echo ""
echo "======================================"
echo "✅ Cleanup completed successfully!"
echo "======================================"
echo ""
echo "Remaining Docker resources:"
docker system df 2>/dev/null || true
echo ""
