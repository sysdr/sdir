#!/bin/bash

# Cleanup Multi-Tenant Demo
echo "🧹 Cleaning up Multi-Tenant Demo..."

# Stop and remove containers
echo "🛑 Stopping services..."
docker-compose down -v

# Remove images (optional)
read -p "🗑️  Remove Docker images as well? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing Docker images..."
    docker-compose down --rmi all -v --remove-orphans
fi

# Clean up node_modules (optional)
read -p "🗑️  Remove node_modules directories? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing node_modules..."
    rm -rf backend/node_modules
    rm -rf frontend/node_modules
    rm -rf tests/node_modules
fi

echo "✅ Cleanup completed!"
