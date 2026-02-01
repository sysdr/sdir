#!/bin/bash
# Stop all services and remove unused Docker resources, then clean cruft from rtb-demo.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Stopping all containers..."

docker-compose down -v 2>/dev/null || true
docker stop $(docker ps -q) 2>/dev/null || true

echo "🗑️  Removing unused Docker resources..."
docker container prune -f
docker image prune -a -f
docker network prune -f
docker volume prune -f

echo "📁 Removing node_modules, venv, .pytest_cache, .pyc, Istio files from rtb-demo..."
for dir in node_modules venv .pytest_cache __pycache__; do
  find "$SCRIPT_DIR" -type d -name "$dir" -not -path "$SCRIPT_DIR" -exec rm -rf {} + 2>/dev/null || true
done
find "$SCRIPT_DIR" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 4 -type d -name 'istio' -exec rm -rf {} + 2>/dev/null || true

echo "✅ Cleanup complete!"
