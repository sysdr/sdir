#!/bin/bash
# Stop containers and remove unused Docker resources.
# Remove node_modules, venv, .pytest_cache, .pyc from this project dir.
# Run from cloud-cost-optimizer: ./cleanup.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Stopping containers ==="
docker stop cloud-cost-optimizer 2>/dev/null && echo "Stopped cloud-cost-optimizer" || true
for c in $(docker ps -aq 2>/dev/null); do
  docker stop "$c" 2>/dev/null || true
done
echo "All containers stopped."

echo ""
echo "=== Removing containers ==="
docker rm cloud-cost-optimizer 2>/dev/null && echo "Removed cloud-cost-optimizer" || true
docker container prune -f
echo "Containers pruned."

echo ""
echo "=== Removing unused Docker resources ==="
docker image prune -a -f --filter "until=0s" 2>/dev/null || docker image prune -a -f
docker volume prune -f
docker network prune -f
echo "Unused images, volumes, networks pruned."

echo ""
echo "=== Project dir cleanup (node_modules, venv, .pytest_cache, .pyc) ==="
for d in node_modules venv .pytest_cache __pycache__; do
  find . -type d -name "$d" ! -path "./.git/*" -exec rm -rf {} + 2>/dev/null || true
done
find . -type f -name '*.pyc' ! -path "./.git/*" -delete 2>/dev/null || true
find . -type f ! -path "./.git/*" \( -iname '*istio*' -o -path '*/istio/*' \) -delete 2>/dev/null || true
echo "Project cleanup done."

echo ""
echo "Cleanup complete."
