#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "============================================"
echo "Cleanup Script - Stopping Services & Cleaning Docker"
echo "============================================"
echo ""

# Stop watermark-demo services if running
echo "Stopping watermark-demo services..."
docker-compose down -v 2>/dev/null || true
echo "✓ Watermark demo services stopped"

# Stop all running Docker containers
echo ""
echo "Stopping all Docker containers..."
CONTAINERS=$(docker ps -aq 2>/dev/null)
if [ -n "$CONTAINERS" ]; then
  docker stop $CONTAINERS 2>/dev/null || true
  echo "✓ All containers stopped"
else
  echo "✓ No containers running"
fi

# Remove stopped containers
echo ""
echo "Removing stopped containers..."
docker container prune -f 2>/dev/null || true

# Remove unused images
echo ""
echo "Removing unused Docker images..."
docker image prune -a -f 2>/dev/null || true

# Remove unused volumes
echo ""
echo "Removing unused Docker volumes..."
docker volume prune -f 2>/dev/null || true

# Remove unused networks
echo ""
echo "Removing unused Docker networks..."
docker network prune -f 2>/dev/null || true

# Clean up build cache
echo ""
echo "Removing Docker build cache..."
docker builder prune -a -f 2>/dev/null || true

# Remove node_modules if any
echo ""
echo "Checking for node_modules directories..."
if find . -name "node_modules" -type d 2>/dev/null | grep -q .; then
  find . -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null || true
  echo "✓ Removed node_modules directories"
else
  echo "✓ No node_modules found"
fi

# Remove Python cache
echo ""
echo "Checking for Python cache files..."
if find . -name "*.pyc" -o -name "__pycache__" -o -name ".pytest_cache" 2>/dev/null | grep -q .; then
  find . -name "*.pyc" -delete 2>/dev/null || true
  find . -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || true
  find . -name ".pytest_cache" -type d -exec rm -rf {} + 2>/dev/null || true
  echo "✓ Removed Python cache files"
else
  echo "✓ No Python cache found"
fi

# Remove venv directories
echo ""
echo "Checking for venv directories..."
if find . -name "venv" -type d 2>/dev/null | grep -q .; then
  find . -name "venv" -type d -exec rm -rf {} + 2>/dev/null || true
  echo "✓ Removed venv directories"
else
  echo "✓ No venv found"
fi

echo ""
echo "============================================"
echo "✓ Cleanup Complete!"
echo "============================================"
echo ""
echo "Docker system status:"
docker system df 2>/dev/null || true
