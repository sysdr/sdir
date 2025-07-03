#!/bin/bash

echo "🧹 Cleaning up Stateless vs Stateful Services Demo..."

# Stop and remove containers
echo "🛑 Stopping services..."
docker-compose down

# Remove volumes
echo "🗑️  Removing volumes..."
docker-compose down -v

# Remove images (optional)
read -p "🤔 Remove built images? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "🗑️  Removing images..."
    docker-compose down --rmi all
fi

# Clean up any dangling containers
echo "🧹 Cleaning up dangling containers..."
docker container prune -f

echo "✅ Cleanup complete!"
