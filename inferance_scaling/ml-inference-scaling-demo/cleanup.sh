#!/bin/bash

echo "🧹 Cleaning up ML Inference Scaling Demo..."

# Stop and remove containers
echo "🛑 Stopping services..."
docker-compose down

# Remove images
echo "🗑️  Removing Docker images..."
docker-compose down --rmi all --volumes --remove-orphans

# Clean up any remaining containers
echo "🔄 Cleaning up remaining containers..."
docker container prune -f

# Clean up volumes
echo "💾 Cleaning up volumes..."
docker volume prune -f

echo "✅ Cleanup completed!"
echo ""
echo "To restart the demo, run: ./demo.sh"
