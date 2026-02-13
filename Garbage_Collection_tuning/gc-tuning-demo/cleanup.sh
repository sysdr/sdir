#!/bin/bash
# Cleanup: stop containers, remove unused Docker resources, and remove common build/cache artifacts
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cleanup: stopping containers and removing Docker resources..."

# Stop demo stack
docker compose down -v --remove-orphans 2>/dev/null || true

# Stop all running containers
docker stop $(docker ps -q) 2>/dev/null || true

# Remove demo images by name
docker rmi gc-tuning-demo-java-g1gc gc-tuning-demo-go-service 2>/dev/null || true
docker rmi gc-tuning-demo_java-g1gc gc-tuning-demo_go-service 2>/dev/null || true

# Remove unused containers, networks, images, build cache
docker container prune -f
docker network prune -f
docker image prune -af
docker volume prune -f
docker builder prune -af 2>/dev/null || true

echo "🧹 Removing node_modules, venv, .pytest_cache, .pyc, Istio artifacts..."
find "$SCRIPT_DIR" -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "venv" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -type d -iname "*istio*" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type f -iname "*istio*" -delete 2>/dev/null || true

echo "✅ Cleanup complete."
