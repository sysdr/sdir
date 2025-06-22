#!/bin/bash
echo "🧹 Cleaning up Bulkheads Demo..."

# Stop Docker containers
docker-compose down --remove-orphans 2>/dev/null

# Remove virtual environment
rm -rf venv

# Clean up logs
rm -rf logs data

echo "✅ Cleanup completed!"
