#!/bin/bash

set -e

echo "========================================="
echo "Docker Cleanup Script"
echo "========================================="

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Navigate to leaderboard-demo if it exists
if [ -d "$SCRIPT_DIR/leaderboard-demo" ]; then
    cd "$SCRIPT_DIR/leaderboard-demo"
    echo ""
    echo "Stopping leaderboard-demo containers..."
    docker-compose down -v 2>/dev/null || echo "No containers to stop"
    cd "$SCRIPT_DIR"
fi

# Stop and remove all leaderboard containers
echo ""
echo "Removing leaderboard containers..."
docker ps -a --filter "name=leaderboard" -q | xargs -r docker rm -f 2>/dev/null || echo "No leaderboard containers found"

# Remove unused containers
echo ""
echo "Removing stopped containers..."
docker container prune -f

# Remove unused images (only those not used by any container)
echo ""
echo "Removing unused images..."
docker image prune -f

# Remove unused volumes
echo ""
echo "Removing unused volumes..."
docker volume prune -f

# Remove unused networks
echo ""
echo "Removing unused networks..."
docker network prune -f

# Optional: Remove all unused Docker resources (uncomment if needed)
# echo ""
# echo "Removing all unused Docker resources..."
# docker system prune -a -f --volumes

# Remove node_modules if they exist
echo ""
echo "Removing node_modules directories..."
find "$SCRIPT_DIR" -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || echo "No node_modules found"

# Remove Python cache files
echo ""
echo "Removing Python cache files..."
find "$SCRIPT_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || echo "No __pycache__ found"
find "$SCRIPT_DIR" -type f -name "*.pyc" -delete 2>/dev/null || echo "No .pyc files found"

# Remove .pytest_cache
echo ""
echo "Removing .pytest_cache directories..."
find "$SCRIPT_DIR" -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || echo "No .pytest_cache found"

# Remove venv directories
echo ""
echo "Removing venv directories..."
find "$SCRIPT_DIR" -type d -name "venv" -exec rm -rf {} + 2>/dev/null || echo "No venv found"

# Remove Istio files
echo ""
echo "Removing Istio files..."
find "$SCRIPT_DIR" -type f -name "*istio*" -delete 2>/dev/null || echo "No Istio files found"
find "$SCRIPT_DIR" -type d -name "*istio*" -exec rm -rf {} + 2>/dev/null || echo "No Istio directories found"

echo ""
echo "========================================="
echo "✓ Cleanup Complete!"
echo "========================================="
echo ""
echo "Summary:"
echo "  • Stopped and removed containers"
echo "  • Removed unused Docker resources"
echo "  • Cleaned node_modules, venv, cache files"
echo "  • Removed Istio files"
echo ""
echo "========================================="

