#!/bin/bash

echo "🧹 Cleaning up Database Scaling Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all

# Remove project directory
cd ..
rm -rf database-scaling-demo

echo "✅ Cleanup complete!"
