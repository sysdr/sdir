#!/bin/bash

set -e

echo "🔨 Building Cache Stampede Mitigation Demo..."
echo "=============================================="

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -d "thundering-herd" ]; then
    echo "⚠️  thundering-herd not found. Running setup.sh first..."
    bash setup.sh
    exit 0
fi

cd thundering-herd

echo ""
echo "📦 Building Docker containers..."
docker-compose build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo ""
    echo "To start: ./start.sh  (or: cd thundering-herd && docker-compose up -d)"
    echo ""
else
    echo ""
    echo "❌ Build failed. Check the errors above."
    exit 1
fi
