#!/bin/bash

echo "🧹 Cleaning up Recommendation System Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all --volumes --remove-orphans

# Clean up any remaining containers
docker container prune -f

# Clean up volumes
docker volume prune -f

echo "✅ Cleanup completed!"
