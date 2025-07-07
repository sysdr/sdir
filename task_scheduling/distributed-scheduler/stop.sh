#!/bin/bash

# Cleanup script for Distributed Task Scheduler Demo

echo "🧹 Cleaning up Distributed Task Scheduler Demo..."

# Stop all running containers
echo "🛑 Stopping all containers..."
docker-compose down

# Remove containers and volumes
echo "📦 Removing containers and volumes..."
docker-compose down -v --remove-orphans

# Remove images
echo "🗑️ Removing built images..."
docker rmi distributed-scheduler_scheduler distributed-scheduler_worker1 distributed-scheduler_worker2 distributed-scheduler_worker3 distributed-scheduler_web-ui 2>/dev/null || true

# Clean up any orphaned containers
echo "🔍 Cleaning up orphaned containers..."
docker container prune -f

# Clean up any orphaned volumes
echo "💾 Cleaning up orphaned volumes..."
docker volume prune -f

# Clean up any orphaned networks
echo "🌐 Cleaning up orphaned networks..."
docker network prune -f

# Remove log files
echo "📝 Cleaning up log files..."
rm -rf logs/*

# Remove Python cache files
echo "🐍 Cleaning up Python cache..."
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -name "*.pyc" -delete 2>/dev/null || true


echo ""
echo "✅ Cleanup completed!"
echo ""
echo "📊 Cleanup Summary:"
echo "   • All containers stopped and removed"
echo "   • All volumes and networks cleaned up"
echo "   • Docker images removed"
echo "   • Log files cleared"
echo "   • Python cache cleaned"
echo ""
echo "🚀 To run the demo again, execute: ./demo.sh"