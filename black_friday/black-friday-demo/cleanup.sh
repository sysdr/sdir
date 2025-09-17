#!/bin/bash

echo "🧹 Cleaning up Black Friday Demo"
echo "==============================="

# Stop all services
echo "🛑 Stopping services..."
docker-compose --profile load-test down

# Remove all containers
echo "🗑️  Removing containers..."
docker-compose rm -f

# Remove images
echo "📦 Removing built images..."
docker rmi -f $(docker images "black-friday-demo*" -q) 2>/dev/null || true

# Remove volumes
echo "💾 Removing volumes..."
docker volume prune -f

# Remove networks
echo "🌐 Removing networks..."
docker network prune -f

echo "✅ Cleanup completed!"
echo ""
echo "All demo components have been removed."
echo "You can run './demo.sh' again to restart the demo."
