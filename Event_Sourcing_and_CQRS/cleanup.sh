#!/bin/bash

echo "🧹 Cleaning up Event Sourcing & CQRS Demo..."
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose not found. Please install Docker Compose."
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker is not running. Please start Docker."
    exit 1
fi

# Stop all running containers
echo "🛑 Stopping all running containers..."
docker stop $(docker ps -q) 2>/dev/null || echo "  ℹ️  No running containers to stop"

# Stop and remove containers, networks, and volumes
echo ""
echo "🗑️  Stopping and removing docker-compose containers, networks, and volumes..."
if docker-compose down -v 2>/dev/null; then
    echo "  ✅ Containers stopped and removed"
else
    echo "  ⚠️  No containers to remove (or already stopped)"
fi

# Remove project-specific images
echo ""
echo "🗑️  Removing project-specific images..."
if docker-compose down --rmi all 2>/dev/null; then
    echo "  ✅ Project images removed"
else
    echo "  ℹ️  No project images to remove"
fi

# Remove unused Docker resources (containers, networks, images, build cache)
echo ""
echo "🧹 Removing unused Docker resources..."
docker system prune -a -f

# Remove unused volumes
echo ""
echo "🗑️  Removing unused volumes..."
docker volume prune -f

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "💡 All Docker containers, images, volumes, and unused resources have been removed."
echo ""
