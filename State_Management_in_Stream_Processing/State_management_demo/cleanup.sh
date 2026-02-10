#!/bin/bash
# Stop containers and remove unused Docker resources for State Management demo.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "State Management Demo - Cleanup"
echo "=================================================="

# Docker compose command
DC_CMD=""
command -v docker-compose &>/dev/null && DC_CMD="docker-compose" || DC_CMD="docker compose"
[ -z "$DC_CMD" ] && DC_CMD="docker compose"

# 1. Stop and remove project containers and volumes
echo ""
echo "[1/4] Stopping project containers..."
$DC_CMD down -v 2>/dev/null || true

# 2. Remove project-related containers (by name pattern)
echo "[2/4] Removing project containers..."
docker ps -aq --filter "name=state_management_in_stream_processing" 2>/dev/null | xargs -r docker rm -f 2>/dev/null || true

# 3. Remove unused Docker resources (dangling images, containers, networks)
echo "[3/4] Pruning unused Docker resources..."
docker container prune -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true
docker image prune -f 2>/dev/null || true

# 4. Remove project build artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)
echo "[4/4] Removing build artifacts..."
find "$SCRIPT_DIR" -type d -name "node_modules" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "venv" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name ".pytest_cache" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "__pycache__" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "istio*" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -type f -path "*istio*" -delete 2>/dev/null || true

echo ""
echo "=================================================="
echo "Cleanup complete."
echo "=================================================="
