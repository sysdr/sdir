#!/bin/bash
# Stop all services and Docker; remove unused Docker resources and project artifacts
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Stopping all Docker services..."

# Stop this project's compose
if [ -f docker-compose.yml ]; then
  docker-compose down -v 2>/dev/null || true
fi

# Stop any remaining running containers
docker stop $(docker ps -q) 2>/dev/null || true

echo "🗑️  Removing unused Docker resources..."
docker container prune -f
docker image prune -af
docker volume prune -f
docker network prune -f

echo "📁 Removing project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)..."
for dir in node_modules venv .venv .pytest_cache __pycache__; do
  find "$SCRIPT_DIR" -type d -name "$dir" -exec rm -rf {} + 2>/dev/null || true
done
find "$SCRIPT_DIR" -name "*.pyc" -delete 2>/dev/null || true
# Istio: install dirs (istio-1.x.x) and istioctl binary
find "$SCRIPT_DIR" -maxdepth 3 -type d -name "istio-*" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 3 -type f -name "istioctl*" -delete 2>/dev/null || true

echo "✅ Cleanup complete!"
