#!/bin/bash

echo "🧹 Cleaning up Graceful Degradation Demo..."

# Stop and remove containers
docker-compose down

# Remove images
docker-compose down --rmi all

# Clean up volumes
docker-compose down -v

echo "✅ Cleanup complete!"
