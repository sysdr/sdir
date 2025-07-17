#!/bin/bash

echo "🧹 Cleaning up Predictive Scaling Demo..."

# Stop and remove containers
docker-compose down

# Remove Docker images
docker rmi predictive-scaling-demo_predictive-scaling 2>/dev/null || true

# Clean up logs
rm -rf logs/*

echo "✅ Cleanup complete!"
