#!/bin/bash

echo "🧹 Cleaning up WebSocket Scaling Demo..."

# Stop and remove containers
docker-compose down -v 2>/dev/null || true

# Remove images
docker rmi $(docker images -q websocket-scaling-demo_* 2>/dev/null) 2>/dev/null || true

# Clean up Docker system
docker system prune -f

# Remove node_modules if they exist
rm -rf server/node_modules

echo "✅ Cleanup completed!"
