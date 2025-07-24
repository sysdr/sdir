#!/bin/bash

# Long-tail Latency Observatory Cleanup Script

set -e

PROJECT_NAME="longtail-latency-demo"

echo "🧹 Cleaning up Long-tail Latency Observatory..."

# Stop and remove containers
if command -v docker-compose &> /dev/null; then
    echo "Stopping Docker services..."
    docker-compose down --volumes --remove-orphans 2>/dev/null || true
fi

# Remove Docker images
echo "Removing Docker images..."
docker rmi $(docker images "*latency*" -q) 2>/dev/null || true
docker system prune -f

echo "✅ Cleanup completed successfully!"
echo "Project files are preserved in: $(pwd)"
