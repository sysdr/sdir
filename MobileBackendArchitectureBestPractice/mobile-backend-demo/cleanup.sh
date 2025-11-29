#!/bin/bash

echo "🧹 Cleaning up Mobile Backend Demo..."

docker-compose down -v 2>/dev/null || true

echo "✅ Cleanup complete!"
