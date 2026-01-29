#!/bin/bash
# Cleanup: stop containers and remove unused Docker resources

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 Stopping Docker Compose services..."
docker compose down -v 2>/dev/null || docker-compose down -v 2>/dev/null || true

echo "🛑 Stopping all running containers..."
docker stop $(docker ps -aq) 2>/dev/null || true

echo "🗑️  Removing stopped containers..."
docker container prune -f

echo "🗑️  Removing unused images..."
docker image prune -a -f

echo "🗑️  Removing unused networks..."
docker network prune -f

echo "🗑️  Removing unused volumes..."
docker volume prune -f

echo "🗑️  Removing build cache..."
docker builder prune -f

echo "🧹 Removing project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)..."
find . -mindepth 1 -type d -name "node_modules" ! -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name "venv" ! -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name ".venv" ! -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name ".pytest_cache" ! -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -type d -name "__pycache__" ! -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
find . -mindepth 1 -name "*.pyc" -delete 2>/dev/null || true
find . -mindepth 1 -name "*.pyo" -delete 2>/dev/null || true
find . -mindepth 1 -type d -name "istio*" ! -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true

echo "✅ Cleanup complete."
