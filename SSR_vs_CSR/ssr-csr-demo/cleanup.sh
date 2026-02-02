#!/bin/bash

# SSR vs CSR Demo - Comprehensive Cleanup Script
# Stops containers, removes unused Docker resources, and cleans project artifacts

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 SSR vs CSR Demo - Cleanup"
echo ""

# 1. Stop project containers
echo "📦 Stopping Docker containers..."
docker-compose down -v 2>/dev/null || true
echo "   ✓ Project containers stopped"

# 2. Stop any running containers from this project
echo ""
echo "🛑 Stopping related containers..."
docker ps -a --filter "name=ssr-csr-demo" -q 2>/dev/null | xargs -r docker stop 2>/dev/null || true
docker ps -a --filter "name=ssr-csr-demo" -q 2>/dev/null | xargs -r docker rm 2>/dev/null || true
echo "   ✓ Done"

# 3. Remove project Docker images
echo ""
echo "🗑️  Removing project Docker images..."
docker rmi ssr-csr-demo-demo 2>/dev/null || true
docker rmi ssr-csr-demo_demo 2>/dev/null || true
echo "   ✓ Done"

# 4. Remove unused Docker resources (stopped containers, unused networks, dangling images)
echo ""
echo "🧼 Pruning unused Docker resources..."
docker container prune -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true
docker image prune -f 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
echo "   ✓ Docker prune complete"

# 5. Remove node_modules
echo ""
echo "📂 Removing node_modules..."
[ -d "$SCRIPT_DIR/node_modules" ] && rm -rf "$SCRIPT_DIR/node_modules" && echo "   Removed node_modules"
echo "   ✓ node_modules removed"

# 6. Remove venv
echo ""
echo "🐍 Removing venv..."
for dir in "$SCRIPT_DIR/venv" "$SCRIPT_DIR/.venv"; do
  [ -d "$dir" ] && rm -rf "$dir" && echo "   Removed $dir"
done
echo "   ✓ venv removed"

# 7. Remove .pytest_cache
echo ""
echo "🧪 Removing .pytest_cache..."
find "$SCRIPT_DIR" -type d -name ".pytest_cache" 2>/dev/null | while read -r d; do rm -rf "$d"; done
echo "   ✓ .pytest_cache removed"

# 8. Remove .pyc and __pycache__
echo ""
echo "🐍 Removing .pyc and __pycache__..."
find "$SCRIPT_DIR" -type f -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "__pycache__" 2>/dev/null | while read -r d; do rm -rf "$d"; done
echo "   ✓ .pyc and __pycache__ removed"

# 9. Remove Istio files
echo ""
echo "☸️  Removing Istio files..."
find "$SCRIPT_DIR" -type d -name "*istio*" 2>/dev/null | while read -r d; do rm -rf "$d"; done
find "$SCRIPT_DIR" -type f -path "*istio*" -delete 2>/dev/null || true
echo "   ✓ Istio files removed"

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "To set up again: bash setup.sh (from project root)"
echo ""
