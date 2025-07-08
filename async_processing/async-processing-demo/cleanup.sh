#!/bin/bash

# Async Processing Demo - Cleanup Script
set -e

echo "🧹 Cleaning up Async Processing Demo..."

# Stop all services
echo "🛑 Stopping services..."
docker-compose down -v

# Remove images
echo "🗑️  Removing Docker images..."
docker-compose down --rmi all --remove-orphans || true

# Remove volumes
echo "💾 Removing volumes..."
docker volume prune -f || true

# Remove networks
echo "🌐 Removing networks..."
docker network prune -f || true

echo "✅ Cleanup complete!"
echo ""
echo "📁 Project files remain in the current directory"
echo "   To remove everything: rm -rf async-processing-demo"
echo ""
