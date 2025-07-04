#!/bin/bash

echo "🧹 Cleaning up Cache Invalidation Demo..."

# Stop and remove containers
docker-compose down -v

# Remove unused images
docker system prune -f

echo "✅ Cleanup complete!"
