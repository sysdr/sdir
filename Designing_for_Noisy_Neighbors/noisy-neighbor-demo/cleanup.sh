#!/bin/bash
# Stop all demo containers and remove unused Docker resources.
# Run from: noisy-neighbor-demo (or project root: bash noisy-neighbor-demo/cleanup.sh)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "=== Stopping demo stack ==="
[ -f "docker-compose.yml" ] && (docker compose down -v --remove-orphans 2>/dev/null) || true
echo "=== Stopping demo containers by name ==="
docker stop nn-redis nn-api nn-loadgen 2>/dev/null || true
docker rm nn-redis nn-api nn-loadgen 2>/dev/null || true
echo "=== Stopping all other running containers ==="
docker stop $(docker ps -q) 2>/dev/null || true
echo "=== Removing unused Docker resources ==="
docker container prune -f
docker network prune -f
docker image prune -af
docker volume prune -f
docker builder prune -af 2>/dev/null || true
echo "=== Removing project-specific images ==="
docker rmi noisy-neighbor-demo-api noisy-neighbor-demo-loadgen 2>/dev/null || true
echo "=== Removing generated artifacts (node_modules, venv, caches, Istio) ==="
find . -depth -type d -name 'node_modules' -exec rm -rf {} + 2>/dev/null || true
find . -depth -type d -name 'venv' -exec rm -rf {} + 2>/dev/null || true
find . -depth -type d -name '.venv' -exec rm -rf {} + 2>/dev/null || true
find . -depth -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
find . -type f -name '*.pyc' -delete 2>/dev/null || true
find . -depth -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find . -depth -type d -name 'istio-*' -exec rm -rf {} + 2>/dev/null || true
find . -type f -name '*.istio.yaml' -delete 2>/dev/null || true
echo "Done. Containers stopped, unused resources and local artifacts removed."
