#!/bin/bash

set -e

echo "🔨 Building Mobile Backend Docker Containers"
echo "============================================="

# Check if mobile-backend-demo directory exists
if [ ! -d "mobile-backend-demo" ]; then
    echo "❌ Error: mobile-backend-demo directory not found!"
    echo "   Please run ./setup.sh first to generate the project structure."
    exit 1
fi

cd mobile-backend-demo

echo ""
echo "📦 Building Docker containers..."
docker-compose build

echo ""
echo "✅ Build Complete!"
echo ""
echo "📝 To start the services, run:"
echo "   cd mobile-backend-demo && docker-compose up -d"
echo ""
echo "   Or use: ./demo.sh"

