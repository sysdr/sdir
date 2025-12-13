#!/bin/bash

echo "🧹 Cleaning up Chaos Engineering Demo..."

cd "$(dirname "$0")"

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
