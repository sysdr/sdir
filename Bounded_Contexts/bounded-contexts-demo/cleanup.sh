#!/bin/bash

echo "🧹 Cleaning up Bounded Contexts Demo..."

# Stop and remove containers
docker-compose down -v --remove-orphans

# Remove images
docker-compose down --rmi all --volumes --remove-orphans

# Remove dangling images
docker image prune -f

echo "✅ Cleanup completed!"
echo "🗑️  All containers, volumes, and images have been removed."
