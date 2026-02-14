#!/bin/bash
# Database Connection Storms - Cleanup script
# Stops containers and removes unused Docker resources
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "======================================"
echo "Database Connection Storms - Cleanup"
echo "======================================"

# 1. Stop project containers
if [ -f "$SCRIPT_DIR/docker-compose.yml" ]; then
    echo ""
    echo "Stopping project containers..."
    (cd "$SCRIPT_DIR" && docker compose down -v --remove-orphans 2>/dev/null) || true
    echo "Project containers stopped."
fi

# 2. Remove project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)
echo ""
echo "Removing project artifacts..."
for dir in node_modules venv .venv .pytest_cache __pycache__; do
  find "$PROJECT_ROOT" -type d -name "$dir" 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true
done
find "$PROJECT_ROOT" -name "*.pyc" -delete 2>/dev/null || true
rm -rf "$PROJECT_ROOT"/istio "$PROJECT_ROOT"/.istio 2>/dev/null || true
find "$PROJECT_ROOT" -type d -name "*istio*" 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true
echo "Artifacts removed."

# 3. Remove unused Docker resources
echo ""
echo "Removing unused Docker resources..."
docker system prune -af --volumes 2>/dev/null || true
echo "Docker cleanup complete."

echo ""
echo "======================================"
echo "Cleanup complete."
echo "======================================"
