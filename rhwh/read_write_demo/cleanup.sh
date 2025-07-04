#!/bin/bash

echo "🧹 Cleaning up Read-Heavy vs Write-Heavy Systems Demo..."

# Stop all running containers (force stop if needed)
echo "🛑 Stopping all containers..."
docker stop $(docker ps -q) 2>/dev/null || true

# Stop and remove containers
echo "🗑️ Removing demo containers..."
docker-compose down

# Remove volumes (optional - uncomment if you want to clear data)
echo "💾 Removing volumes..."
docker-compose down -v

# Remove built images (optional)
echo "🖼️ Removing built images..."
docker-compose down --rmi all

# Clean up any dangling resources
echo "🧽 Cleaning up dangling resources..."
docker system prune -f

echo "✅ Cleanup completed!"
