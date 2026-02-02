#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🔨 Building SSR vs CSR Demo..."
echo ""

# Check for duplicate services and stop them
echo "🔍 Checking for duplicate services..."
if docker-compose ps -q 2>/dev/null | grep -q .; then
    echo "   Stopping existing containers..."
    docker-compose down 2>/dev/null || true
fi

# Build Docker containers
echo "🐳 Building Docker containers..."
docker-compose build

echo ""
echo "✅ Build complete!"
echo ""
echo "To start: ./start.sh"
echo ""
