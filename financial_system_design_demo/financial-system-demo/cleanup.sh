#!/bin/bash

echo "🧹 Cleaning up Financial System Demo..."

echo "🛑 Stopping all services..."
docker-compose down -v --remove-orphans 2>/dev/null

echo "🗑️ Removing Docker images..."
docker-compose down --rmi all 2>/dev/null

echo "🧼 Cleaning up any remaining containers..."
docker container prune -f 2>/dev/null

echo "🧽 Cleaning up any remaining volumes..."
docker volume prune -f 2>/dev/null

echo "✅ Cleanup completed!"
echo "Docker resources have been removed."
echo "Note: To remove this directory, go to the parent directory and run: rm -rf financial-system-demo"
