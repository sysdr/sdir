#!/bin/bash

echo "🧹 Cleaning up AI-Powered Application Demo..."

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
