#!/bin/bash

echo "🧹 Cleaning up Blue-Green Deployment Demo..."

# Stop and remove containers
echo "🛑 Stopping containers..."
docker compose down -v

# Remove images
echo "🗑️ Removing images..."
docker compose down --rmi all --volumes --remove-orphans 2>/dev/null || true

# Clean up any dangling images
echo "🧹 Cleaning up dangling images..."
docker image prune -f

# Clean up networks
echo "🌐 Cleaning up networks..."
docker network prune -f

echo "✅ Cleanup complete!"
echo ""
echo "To restart the demo, run: ./demo.sh"
