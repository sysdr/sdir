#!/bin/bash

# Cleanup script
echo "🧹 Cleaning up backpressure demo..."

docker-compose down -v
docker system prune -f

echo "✅ Cleanup completed"
