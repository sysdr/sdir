#!/bin/bash

set -e

echo "======================================"
echo "Building Load Shedding & Request Prioritization Demo"
echo "======================================"

cd "$(dirname "$0")"

if [ ! -f "package.json" ]; then
    echo "❌ Error: package.json not found. Run setup.sh first."
    exit 1
fi

echo ""
echo "📦 Installing dependencies..."
npm install

echo ""
echo "🐳 Building Docker images..."
docker-compose build

echo ""
echo "======================================"
echo "✅ Build complete!"
echo "======================================"
echo ""
echo "Start with: ./start.sh"
echo ""
