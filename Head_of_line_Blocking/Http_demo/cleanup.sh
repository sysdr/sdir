#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cleanup: Stopping containers and removing unused Docker resources..."
echo ""

# 1. Stop and remove project containers
if [ -f "docker-compose.yml" ]; then
  echo "   Stopping docker-compose services..."
  docker-compose down -v 2>/dev/null || true
fi

# 2. Stop all running containers
echo "   Stopping all containers..."
docker stop $(docker ps -aq) 2>/dev/null || true

# 3. Remove all stopped containers
echo "   Removing stopped containers..."
docker container prune -f

# 4. Remove unused images
echo "   Removing unused Docker images..."
docker image prune -a -f

# 5. Remove unused volumes
echo "   Removing unused volumes..."
docker volume prune -f

# 6. Remove unused networks
echo "   Removing unused networks..."
docker network prune -f

# 7. Full system prune (optional - removes build cache too)
echo "   Running docker system prune..."
docker system prune -af --volumes

# 8. Remove node_modules, venv, .pytest_cache, .pyc, Istio from project
echo "   Removing project artifacts..."
find "$SCRIPT_DIR" -type d -name "node_modules" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "venv" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name ".pytest_cache" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "__pycache__" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -path "*istio*" -type f -delete 2>/dev/null || true
find "$SCRIPT_DIR" -path "*istio*" -type d -depth 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true

echo ""
echo "✅ Cleanup complete"
echo ""
echo "To restart: run ./setup.sh or ./start.sh"
