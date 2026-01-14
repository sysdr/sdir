#!/bin/bash

echo "🧹 Cleaning up Global Payment System..."

cd "$(dirname "$0")"

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
