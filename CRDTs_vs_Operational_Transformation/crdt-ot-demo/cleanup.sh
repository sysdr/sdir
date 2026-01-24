#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Cleaning up..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all

echo "✅ Cleanup complete!"
