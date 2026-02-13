#!/bin/bash
# Stop containers and remove unused Docker resources.
# Also removes node_modules, venv, .pytest_cache, .pyc, and Istio artifacts from this directory.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Stopping containers and cleaning up..."

# Stop this demo stack if present
if [ -f "docker-compose.yml" ]; then
  echo "Stopping tail-latency-demo services..."
  docker-compose down -v 2>/dev/null || true
fi

# Stop any remaining running containers
echo "Stopping all Docker containers..."
docker stop $(docker ps -aq) 2>/dev/null || true

# Remove containers, images, networks, build cache
echo "Removing unused Docker resources..."
docker container prune -f
docker image prune -f
docker network prune -f
docker volume prune -f
docker system prune -f 2>/dev/null || true

# Remove project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)
echo "Removing project artifacts..."
find "$SCRIPT_DIR" -mindepth 1 -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "venv" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -name "*.pyo" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -iname "*istio*" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type f -path "*istio*" \( -name "*.yaml" -o -name "*.yml" \) -delete 2>/dev/null || true

echo "✅ Cleanup complete!"
