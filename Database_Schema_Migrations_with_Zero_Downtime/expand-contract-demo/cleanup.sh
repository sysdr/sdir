#!/bin/bash
# Stop all project containers and remove unused Docker resources.
# Also removes node_modules, venv, .pytest_cache, .pyc, Istio artifacts from this project.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/expand-contract-demo/setup.sh" ]; then
  DEMO_DIR="$SCRIPT_DIR"
else
  DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
cd "$SCRIPT_DIR"

echo "▶  Stopping project containers..."
if [ -f "$DEMO_DIR/docker-compose.yml" ]; then
  (cd "$DEMO_DIR" && docker compose down -v --remove-orphans 2>/dev/null) || true
fi
echo "  Done."

echo ""
echo "▶  Stopping any remaining running containers..."
docker stop $(docker ps -q) 2>/dev/null || true
echo "  Done."

echo ""
echo "▶  Removing stopped containers, unused images, volumes, networks..."
docker container prune -f
docker image prune -af
docker volume prune -f
docker network prune -f
echo "  Done."

echo ""
echo "▶  Removing node_modules, venv, .pytest_cache, .pyc, Istio files from project..."
find "$SCRIPT_DIR" -maxdepth 5 -type d -name "node_modules" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 5 -type d -name "venv" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 5 -type d -name ".pytest_cache" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 5 -type d -name "__pycache__" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 5 -type f -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 5 -type d -name "istio" -prune -exec rm -rf {} \; 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 4 -type d -path "*/install/istio" -prune -exec rm -rf {} \; 2>/dev/null || true
echo "  Done."

echo ""
echo "✅ Cleanup complete."
