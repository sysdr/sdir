#!/bin/bash

echo "🧹 Cleaning up UDP vs TCP Gaming Demo..."

cd "$(dirname "$0")"

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
