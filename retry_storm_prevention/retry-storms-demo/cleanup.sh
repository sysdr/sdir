#!/bin/bash

echo "🛑 Stopping Retry Storms Demo..."

# Stop and remove containers
docker-compose down -v

# Remove unused images
echo "🧹 Cleaning up Docker images..."
docker system prune -f

echo "✅ Cleanup complete!"
