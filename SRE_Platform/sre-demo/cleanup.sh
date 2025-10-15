#!/bin/bash

echo "🧹 Cleaning up SRE Demo..."

# Stop and remove containers
echo "🛑 Stopping services..."
docker-compose down

# Remove images
echo "🗑️ Removing images..."
docker-compose down --rmi all

# Remove volumes
echo "💾 Removing volumes..."
docker-compose down --volumes

# Remove networks
echo "🌐 Removing networks..."
docker network rm sre-network 2>/dev/null || true

# Clean up any remaining containers
echo "🔄 Cleaning up containers..."
docker container prune -f

echo "✅ Cleanup complete!"
