#!/bin/bash

echo "🧹 Cleaning up Event-Driven Architecture Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all

# Remove volumes
docker volume prune -f

echo "✅ Cleanup complete!"
