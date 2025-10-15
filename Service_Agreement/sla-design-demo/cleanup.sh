#!/bin/bash

echo "🧹 Cleaning up SLA Design Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all

echo "✅ Cleanup complete!"
