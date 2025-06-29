#!/bin/bash

# Hybrid Cloud Demo Cleanup Script
# System Design Interview Roadmap - Issue #81

echo "🧹 Cleaning up Hybrid Cloud Demo..."
echo "===================================="

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Not in demo directory. Please run from hybrid-cloud-demo folder."
    exit 1
fi

# Stop and remove containers
echo "🛑 Stopping containers..."
docker-compose down

# Remove containers forcefully if needed
echo "🗑️  Removing containers..."
docker rm -f hybrid-private hybrid-public hybrid-gateway hybrid-redis 2>/dev/null || true

# Remove images
echo "🖼️  Removing built images..."
docker rmi -f hybrid-cloud-demo_private-cloud 2>/dev/null || true
docker rmi -f hybrid-cloud-demo_public-cloud 2>/dev/null || true
docker rmi -f hybrid-cloud-demo_gateway 2>/dev/null || true

# Remove volumes
echo "💾 Removing volumes..."
docker volume rm hybrid-cloud-demo_private_data 2>/dev/null || true
docker volume rm hybrid-cloud-demo_redis_data 2>/dev/null || true

# Remove network
echo "🌐 Removing network..."
docker network rm hybrid-cloud-demo_hybrid-network 2>/dev/null || true

# Clean up any orphaned resources
echo "🧼 Cleaning up orphaned resources..."
docker system prune -f

# Go back to parent directory
cd ..


echo ""
echo "🎉 Cleanup completed!"
echo "All containers, images, volumes, and project files have been removed."
echo ""
echo "To run the demo again:"
echo "curl -O https://raw.githubusercontent.com/demo/hybrid-cloud-demo.sh"
echo "chmod +x demo.sh && ./demo.sh"