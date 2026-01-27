#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cleaning up HFT Latency Demo..."

# Stop and remove project containers and volumes
echo "Stopping containers..."
docker-compose down -v 2>/dev/null || docker compose down -v 2>/dev/null || true

# Stop any remaining running containers
echo "Stopping all running containers..."
docker stop $(docker ps -aq) 2>/dev/null || true

# Remove project containers (even if stopped)
echo "Removing project containers..."
docker rm -f $(docker ps -aq --filter "name=high-frequency_trading_architecture" 2>/dev/null) 2>/dev/null || true

# Remove unused Docker resources
echo "Pruning unused containers..."
docker container prune -f

echo "Pruning unused images..."
docker image prune -a -f

echo "Pruning unused volumes..."
docker volume prune -f

echo "Pruning unused networks..."
docker network prune -f

echo "System prune (all unused build cache, etc.)..."
docker system prune -a -f --volumes

# Remove node_modules, venv, .pytest_cache, .pyc, Istio from project (mindepth 1 = avoid .)
echo "Removing node_modules, venv, .pytest_cache, .pyc, Istio..."
find . -mindepth 1 -type d -name 'node_modules' -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name 'venv' -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type f -name '*.pyc' -delete 2>/dev/null || true
find . -mindepth 1 -type f -name '*.pyo' -delete 2>/dev/null || true
find . -mindepth 1 -type d -name 'istio' -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name 'istio-*' -exec rm -rf {} + 2>/dev/null || true

echo "✅ Cleanup complete!"
