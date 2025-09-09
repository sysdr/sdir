#!/bin/bash

echo "🧹 Cleaning up Incident Response Automation Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all

# Remove volumes
docker volume prune -f

# Remove networks
docker network prune -f

echo "✅ Cleanup complete!"
