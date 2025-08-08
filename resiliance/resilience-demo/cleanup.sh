#!/bin/bash

echo "🧹 Cleaning up Resilience Testing Demo..."

# Stop and remove containers
docker-compose down -v

# Remove unused Docker resources
docker system prune -f

# Clean up any test data
rm -rf node_modules 2>/dev/null || true

echo "✅ Cleanup completed"
