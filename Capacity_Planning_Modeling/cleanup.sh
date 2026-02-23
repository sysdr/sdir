#!/bin/bash
# =============================================================================
# Capacity Planning Modeling — Full cleanup
# Stops all containers, removes unused Docker resources, and project cruft
# =============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Stopping all containers..."
docker compose -f littles-law-demo/docker-compose.yml down -v --remove-orphans 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true

echo "🗑️  Removing project Docker images..."
for img in littles-law-demo-api-gateway littles-law-demo-app-server littles-law-demo-load-generator littles-law-demo-dashboard; do
  docker rmi "$img" 2>/dev/null || true
done

echo "🧽 Pruning unused Docker resources..."
docker container prune -f
docker image prune -f
docker volume prune -f
docker network prune -f

echo "📁 Removing project cruft (node_modules, venv, caches, Istio)..."
find "$SCRIPT_DIR" -mindepth 1 -type d -name "node_modules" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "venv" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name ".pytest_cache" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "__pycache__" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type f -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name "istio" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type f -path "*istio*" -delete 2>/dev/null || true

echo "✅ Cleanup complete."
