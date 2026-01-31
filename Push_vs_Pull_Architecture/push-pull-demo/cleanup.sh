#!/bin/bash
# Cleanup: stop demo containers, remove unused Docker resources, and remove local artifacts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Stopping Docker containers and cleaning resources ==="

# Stop push-pull-demo stack
echo "Stopping push-pull-demo stack..."
docker-compose down -v 2>/dev/null || true

# Stop all running containers
echo "Stopping all running containers..."
docker stop $(docker ps -q) 2>/dev/null || true

# Remove containers, networks, images, build cache
echo "Removing unused containers..."
docker container prune -f

echo "Removing unused networks..."
docker network prune -f

echo "Removing unused images (dangling)..."
docker image prune -f

echo "Removing unused volumes..."
docker volume prune -f

echo "Removing build cache..."
docker builder prune -f 2>/dev/null || true

echo ""
echo "=== Removing local artifacts (node_modules, venv, .pytest_cache, .pyc, Istio) ==="

find "$SCRIPT_DIR" -mindepth 1 -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "venv" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type f -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "istio*" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type f -path "*istio*" -delete 2>/dev/null || true

echo "✓ Cleanup complete"
