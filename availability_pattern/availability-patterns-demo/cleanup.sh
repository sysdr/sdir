#!/bin/bash

echo "🧹 Cleaning up Availability Patterns Demo..."

# Stop and remove containers
docker-compose down -v

# Remove Docker images
docker-compose down --rmi all --volumes --remove-orphans

# Clean up node modules
rm -rf node_modules

echo "✨ Cleanup complete!"
