#!/bin/bash

echo "🧹 Cleaning up Health Check Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all

# Remove networks
docker network prune -f

echo "✅ Cleanup complete!"
