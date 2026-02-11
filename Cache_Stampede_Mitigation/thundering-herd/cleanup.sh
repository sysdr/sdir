#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cache Stampede Mitigation – cleanup"
echo "======================================"

echo ""
echo "Stopping containers and removing volumes..."
docker-compose down -v 2>/dev/null || true
echo "Done."

echo ""
echo "Removing unused Docker containers..."
docker container prune -f 2>/dev/null || true
echo "Removing unused Docker networks..."
docker network prune -f 2>/dev/null || true
echo "Removing dangling Docker images..."
docker image prune -f 2>/dev/null || true

echo ""
echo "Removing project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)..."
for dir in node_modules venv .venv .pytest_cache istio; do
  find "$PROJECT_ROOT" -type d -name "$dir" -not -path "$PROJECT_ROOT" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
done
find "$PROJECT_ROOT" -type d -name '__pycache__' -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$PROJECT_ROOT" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
find "$PROJECT_ROOT" -type f -path '*istio*' -delete 2>/dev/null || true
echo "Done."

echo ""
echo "✅ Cleanup complete."
