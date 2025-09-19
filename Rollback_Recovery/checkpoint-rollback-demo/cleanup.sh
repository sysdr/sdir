#!/bin/bash

echo "🧹 Cleaning up Checkpoint and Rollback Recovery Demo..."

# Stop and remove containers
docker-compose down -v

# Remove images
docker-compose down --rmi all || true

# Clean up logs and checkpoints
rm -rf logs/* checkpoints/* || true

echo "✅ Cleanup complete!"
