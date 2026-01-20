#!/bin/bash

echo "🧹 Cleaning up Geofencing Demo..."

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
