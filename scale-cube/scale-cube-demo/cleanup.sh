#!/bin/bash

echo "🧹 Cleaning up Scale Cube Demo..."

# Stop and remove the manually created web UI container (if it exists)
echo "🔄 Stopping manual web UI container..."
docker stop scale-cube-web-ui 2>/dev/null || true
docker rm scale-cube-web-ui 2>/dev/null || true

# Stop and remove all containers
echo "🔄 Stopping all services..."
docker-compose down -v

# Remove Docker images
echo "🗑️ Removing Docker images..."
docker-compose down --rmi all

# Clean up any dangling containers or networks
echo "🧹 Cleaning up dangling resources..."
docker system prune -f

echo ""
echo "✅ Cleanup completed!"
echo ""
echo "📋 Cleanup Summary:"
echo "   - ✅ All containers stopped and removed"
echo "   - ✅ All volumes removed"
echo "   - ✅ All custom images removed"
echo "   - ✅ Networks cleaned up"
echo "   - ✅ Manual web UI container removed"
echo ""
echo "🚀 To restart the demo:"
echo "   ./demo.sh"
