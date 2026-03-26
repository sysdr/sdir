#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping project containers..."
docker compose down -v --remove-orphans || true

echo "Stopping any remaining running containers..."
docker ps -q | xargs -r docker stop

echo "Pruning unused Docker resources..."
docker container prune -f
docker image prune -af
docker volume prune -f
docker network prune -f

echo "Docker cleanup complete."
