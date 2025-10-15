#!/bin/bash

echo "🧹 Cleaning up Cascading Failures Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all --volumes --remove-orphans

echo "✅ Cleanup complete!"
