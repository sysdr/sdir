#!/bin/bash

set -e

echo "🧹 Cleaning up Load Shedding Demo..."
cd "$(dirname "$0")"

# Stop and remove project containers and volumes
echo "Stopping and removing project containers..."
docker-compose down -v 2>/dev/null || true

# Remove unused containers, networks, images
echo "Removing unused Docker resources..."
docker container prune -f
docker network prune -f
docker image prune -af

echo "✅ Cleanup complete!"
