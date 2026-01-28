#!/bin/bash

echo "🧹 Cleaning up Chat System Demo..."

cd chat-system

# Stop and remove containers
docker-compose down -v

echo "✅ Cleanup complete!"
