#!/bin/bash

echo "🧹 Cleaning up Mobile Backend Demo..."

cd mobile-backend-demo 2>/dev/null || true

docker-compose down -v 2>/dev/null || true

cd ..
rm -rf mobile-backend-demo

echo "✅ Cleanup complete!"
