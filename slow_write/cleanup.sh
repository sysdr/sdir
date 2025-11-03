#!/bin/bash

echo "🧹 Cleaning up Slow Log Writes Demo..."

cd slow-log-demo 2>/dev/null || {
  echo "⚠️  Demo directory not found"
  exit 0
}

echo "🛑 Stopping containers..."
docker-compose down -v

echo "🗑️  Removing Docker images..."
docker-compose rm -f
docker rmi slow-log-demo_app 2>/dev/null || true


echo "✅ Cleanup complete!"