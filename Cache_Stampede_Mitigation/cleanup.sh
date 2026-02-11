#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cache Stampede Mitigation – cleanup"
echo "======================================"

# Stop project containers and remove volumes
if [ -d "thundering-herd" ]; then
  echo ""
  echo "Stopping containers and removing volumes..."
  (cd thundering-herd && docker-compose down -v 2>/dev/null) || true
  echo "Done."
fi

# Remove unused Docker resources (containers, networks, dangling images)
echo ""
echo "Removing unused Docker containers..."
docker container prune -f 2>/dev/null || true
echo "Removing unused Docker networks..."
docker network prune -f 2>/dev/null || true
echo "Removing dangling Docker images..."
docker image prune -f 2>/dev/null || true

# Remove node_modules, venv, .pytest_cache, .pyc, Istio artifacts from project
echo ""
echo "Removing project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)..."
for dir in node_modules venv .venv .pytest_cache istio; do
  find "$SCRIPT_DIR" -type d -name "$dir" -not -path "$SCRIPT_DIR" -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
done
find "$SCRIPT_DIR" -type d -name '__pycache__' -print0 2>/dev/null | xargs -0 rm -rf 2>/dev/null || true
find "$SCRIPT_DIR" -type f \( -name '*.pyc' -o -name '*.pyo' \) -delete 2>/dev/null || true
find "$SCRIPT_DIR" -type f -path '*istio*' -delete 2>/dev/null || true
echo "Done."

echo ""
echo "✅ Cleanup complete."
