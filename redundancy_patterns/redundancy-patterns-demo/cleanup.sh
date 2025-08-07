#!/bin/bash

echo "🧹 Cleaning up Redundancy Patterns Demo..."

echo "🛑 Stopping Docker containers..."
docker-compose down -v

echo "🗑️ Removing Docker images..."
docker-compose down --rmi all

echo "🧽 Removing volumes..."
docker volume prune -f

echo "✅ Cleanup complete!"
