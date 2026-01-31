#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Cleaning up Kappa vs Lambda Architecture project"
echo "=================================================="

# 1. Stop project containers
echo ""
echo "[1/5] Stopping containers..."
if [ -f "docker-compose.yml" ]; then
  docker compose down -v 2>/dev/null || docker-compose down -v 2>/dev/null || true
fi
echo "   Containers stopped."

# 2. Remove unused Docker containers
echo ""
echo "[2/5] Removing stopped containers..."
docker container prune -f 2>/dev/null || true

# 3. Remove unused Docker images
echo ""
echo "[3/5] Removing unused images..."
docker image prune -f 2>/dev/null || true

# 4. Remove unused Docker resources (networks, build cache)
echo ""
echo "[4/5] Pruning Docker system (unused resources)..."
docker system prune -f 2>/dev/null || true

# 5. Remove node_modules, venv, .pytest_cache, .pyc, Istio from project
echo ""
echo "[5/5] Removing node_modules, venv, .pytest_cache, .pyc, Istio..."
for d in node_modules venv .pytest_cache istio __pycache__; do
  find "$SCRIPT_DIR" -type d -name "$d" -prune -exec rm -rf {} \; 2>/dev/null || true
done
find "$SCRIPT_DIR" -type f -name '*.pyc' -delete 2>/dev/null || true
echo "   Project artifacts removed (if any)."

echo ""
echo "=================================================="
echo "Cleanup complete"
echo "=================================================="
