#!/bin/bash

echo "🧹 Cleaning up Self-Healing Systems Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
echo "🗑️ Removing Docker images..."
docker images --format "table {{.Repository}}:{{.Tag}}" | grep "self-healing-demo" | awk '{print $1}' | xargs -r docker rmi

# Clean up networks
docker network prune -f

echo "✅ Cleanup complete!"
