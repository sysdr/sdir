#!/bin/bash

echo "🧹 Cleaning up Push Notification System Demo..."

# Stop and remove containers
docker compose down -v

# Remove images
docker rmi $(docker images "push-notification-*" -q) 2>/dev/null || true

# Clean up volumes
docker volume prune -f

echo "✅ Cleanup complete!"
