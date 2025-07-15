#!/bin/bash

echo "🧹 Cleaning up Hot Partition Demo"
echo "================================="

# Stop and remove containers
echo "🛑 Stopping services..."
docker-compose down -v

# Remove unused images
echo "🗑️ Cleaning up Docker images..."
docker image prune -f

# Remove any leftover data
echo "📁 Cleaning up data files..."
rm -rf logs/* data/*

echo "✅ Cleanup complete!"
echo ""
echo "To restart the demo, run: ./demo.sh"
