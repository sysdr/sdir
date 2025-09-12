#!/bin/bash

echo "🧹 Cleaning up Runbook Management System..."

# Stop and remove containers
docker-compose down --volumes --remove-orphans

# Remove images
docker rmi $(docker images -q --filter "reference=*runbook*") 2>/dev/null || true

# Clean up test dependencies
rm -rf tests/node_modules/ 2>/dev/null || true

# Remove data directory
rm -rf data/ 2>/dev/null || true

echo "✅ Cleanup completed!"
