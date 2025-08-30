#!/bin/bash

echo "🧹 Cleaning up Rolling Deployment Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all

# Remove unused networks
docker network prune -f

echo "✅ Cleanup completed!"
