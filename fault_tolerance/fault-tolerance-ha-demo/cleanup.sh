#!/bin/bash

echo "🛑 Stopping Fault Tolerance vs High Availability Demo"

echo "🐳 Stopping Docker containers..."
docker-compose down -v

echo "🗑️ Removing Docker images..."
docker-compose down --rmi all --volumes --remove-orphans

echo "🧹 Cleaning up node_modules..."
find . -name "node_modules" -type d -exec rm -rf {} +

echo "✅ Cleanup complete!"
