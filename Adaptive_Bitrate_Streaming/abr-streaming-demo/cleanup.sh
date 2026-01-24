#!/bin/bash

echo "🧹 Cleaning up ABR Streaming Demo..."

docker-compose down -v
docker system prune -f

echo "✅ Cleanup complete!"
