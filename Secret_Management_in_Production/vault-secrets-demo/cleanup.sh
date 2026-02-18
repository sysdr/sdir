#!/bin/bash
# Stop project containers, remove unused Docker resources, and clean project artifacts.
# Run from vault-secrets-demo: ./cleanup.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="${VAULT_DEMO_DIR:-$SCRIPT_DIR}"

echo "🧹 Cleanup: stopping containers and removing unused Docker resources..."
echo ""

# Stop project demo stack
if [[ -f "$DEMO_DIR/docker-compose.yml" ]]; then
  (cd "$DEMO_DIR" && docker compose down -v --remove-orphans 2>/dev/null || docker-compose down -v --remove-orphans 2>/dev/null) || true
  docker rmi vault-secrets-demo-backend 2>/dev/null || true
fi

# Stop any remaining running containers
docker ps -aq 2>/dev/null | xargs -r docker stop 2>/dev/null || true

# Remove stopped containers
docker container prune -f 2>/dev/null || true

# Remove unused images (dangling and optionally unused)
docker image prune -af 2>/dev/null || true

# Remove unused volumes
docker volume prune -f 2>/dev/null || true

# Remove unused networks
docker network prune -f 2>/dev/null || true

# Remove project artifacts (if present)
for dir in node_modules venv .venv .pytest_cache __pycache__; do
  find "$SCRIPT_DIR" -maxdepth 4 -depth -type d -name "$dir" -exec rm -rf {} + 2>/dev/null || true
done
find "$SCRIPT_DIR" -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -maxdepth 4 -depth -type d -name "*istio*" -exec rm -rf {} + 2>/dev/null || true

echo "✅ Cleanup complete."
echo "   Containers stopped, unused images/volumes/networks removed."
echo "   node_modules, venv, .pytest_cache, .pyc, Istio artifacts removed if present."
