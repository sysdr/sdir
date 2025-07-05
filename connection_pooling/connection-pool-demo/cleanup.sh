#!/bin/bash

# Connection Pool Demo - Cleanup Script
echo "🧹 Cleaning up Connection Pool Demo..."

# Stop and remove containers
echo "🛑 Stopping containers..."
docker-compose down -v

# Remove images
echo "🗑️  Removing Docker images..."
docker-compose down --rmi all --volumes --remove-orphans

# Remove any dangling images
echo "🔍 Removing dangling images..."
docker image prune -f


echo "🎉 Cleanup completed!"
echo ""
echo "To restart the demo:"
echo "1. Run: ./demo.sh"
echo "2. Or follow the setup instructions again"
