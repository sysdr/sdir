#!/bin/bash

echo "🧹 Cleaning up Multi-Region Failover Demo..."

# Stop and remove containers
docker-compose down -v

# Remove built images
docker rmi $(docker images -q "*failover*" 2>/dev/null) 2>/dev/null || true

# Clean up logs
rm -rf logs/*

echo "✅ Cleanup completed!"
