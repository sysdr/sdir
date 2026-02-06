#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cleanup: Stopping containers and removing Docker resources..."
echo ""

# Stop locking-demo containers
echo "Stopping locking-demo containers..."
docker-compose down -v 2>/dev/null || true
docker network rm locking-demo-network 2>/dev/null || true

# Stop any other running containers
echo "Stopping all running containers..."
docker stop $(docker ps -q) 2>/dev/null || true

# Remove stopped containers
echo "Removing stopped containers..."
docker container prune -f

# Remove unused images
echo "Removing unused images..."
docker image prune -a -f

# Remove unused volumes
echo "Removing unused volumes..."
docker volume prune -f

# Remove unused networks
echo "Removing unused networks..."
docker network prune -f

# Remove build cache
echo "Removing build cache..."
docker builder prune -f 2>/dev/null || true

echo ""
echo "🧹 Removing project artifacts..."

# Remove node_modules
find . -type d -name "node_modules" 2>/dev/null | while read -r d; do rm -rf "$d"; done

# Remove venv
find . -type d -name "venv" 2>/dev/null | while read -r d; do rm -rf "$d"; done

# Remove .pytest_cache
find . -type d -name ".pytest_cache" 2>/dev/null | while read -r d; do rm -rf "$d"; done

# Remove .pyc and __pycache__
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type d -name "__pycache__" 2>/dev/null | while read -r d; do rm -rf "$d"; done

# Remove Istio files and directories
find . -type f -iname "*istio*" -delete 2>/dev/null || true
find . -type d -iname "*istio*" 2>/dev/null | while read -r d; do rm -rf "$d"; done

echo ""
echo "✅ Cleanup complete"
