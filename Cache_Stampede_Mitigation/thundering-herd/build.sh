#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building Cache Stampede Mitigation Demo..."
echo "=============================================="

if [ ! -f "docker-compose.yml" ]; then
    echo "⚠️  docker-compose.yml not found. Run ../setup.sh first."
    exit 1
fi

echo ""
echo "📦 Building Docker containers..."
docker-compose build

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo ""
    echo "To start: ./start.sh  (or: docker-compose up -d)"
    echo ""
else
    echo ""
    echo "❌ Build failed. Check the errors above."
    exit 1
fi
