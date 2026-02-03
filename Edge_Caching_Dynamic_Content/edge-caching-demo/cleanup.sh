#!/bin/bash

set -e

echo "🧹 Edge Caching Demo - Cleanup"
echo "================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Resolve docker-compose command
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
fi

# Stop and remove project containers
echo ""
echo "🛑 Stopping and removing project containers..."
if [ -n "$DOCKER_COMPOSE_CMD" ] && [ -f "docker-compose.yml" ]; then
  $DOCKER_COMPOSE_CMD down -v 2>/dev/null || true
  echo "✅ Project containers stopped"
fi

# Stop all running containers
echo ""
echo "🛑 Stopping all running Docker containers..."
docker ps -q | xargs -r docker stop 2>/dev/null || echo "  No running containers"

# Remove stopped containers
echo ""
echo "🗑️  Removing stopped containers..."
docker container prune -f

# Remove unused images
echo ""
echo "🗑️  Removing unused Docker images..."
docker image prune -af

# Remove unused volumes
echo ""
echo "🗑️  Removing unused volumes..."
docker volume prune -f

# Remove unused networks
echo ""
echo "🧹 Removing unused networks..."
docker network prune -f

# Full system prune (optional - removes all unused data)
echo ""
echo "🧹 Docker system prune..."
docker system prune -af --volumes 2>/dev/null || true

# Remove project-specific artifacts
echo ""
echo "🗑️  Removing node_modules, venv, .pytest_cache, .pyc, Istio..."
find . -type d -name "node_modules" 2>/dev/null | while read d; do rm -rf "$d"; done
find . -type d -name "venv" 2>/dev/null | while read d; do rm -rf "$d"; done
find . -type d -name ".venv" 2>/dev/null | while read d; do rm -rf "$d"; done
find . -type d -name ".pytest_cache" 2>/dev/null | while read d; do rm -rf "$d"; done
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type f -name "*.pyo" -delete 2>/dev/null || true
find . -path "*istio*" 2>/dev/null | while read f; do rm -rf "$f"; done

echo ""
echo "================================"
echo "✅ Cleanup completed!"
echo "================================"
echo ""
echo "Run setup.sh from project root to regenerate, then start.sh to run."
echo ""
