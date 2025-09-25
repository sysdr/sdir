#!/bin/bash

echo "🧹 Cleaning up API Versioning Demo..."

# Stop Docker containers
if command -v docker-compose &> /dev/null; then
    docker-compose down -v
    docker-compose rm -f
fi

# Kill any running Node processes
pkill -f "node src/server.js" || true

# Clean up files
rm -rf node_modules logs/*.log

echo "✅ Cleanup complete"
