#!/bin/bash
# Stop containers and remove unused Docker resources
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Stopping all containers ==="
docker compose down -v 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true

echo "=== Removing stopped containers ==="
docker container prune -f

echo "=== Removing unused images ==="
docker image prune -a -f

echo "=== Removing unused volumes ==="
docker volume prune -f

echo "=== Removing unused networks ==="
docker network prune -f

echo "=== Full system prune ==="
docker system prune -a -f --volumes

echo "✅ Cleanup complete"
