#!/bin/bash

set -e

echo "🚀 Starting Rolling Deployment Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Install Node.js dependencies
echo "📦 Installing dependencies..."
npm install

# Build and start services
echo "🏗️ Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 15

# Check if services are responding
echo "🔍 Checking service health..."
for i in {1..30}; do
    if curl -s http://localhost:8080/admin/status > /dev/null; then
        echo "✅ Services are ready!"
        break
    fi
    echo "Waiting for services... ($i/30)"
    sleep 2
done

# Run tests
echo "🧪 Running tests..."
node tests/test.js

echo ""
echo "🎉 Rolling Deployment Demo is ready!"
echo ""
echo "📊 Dashboard: http://localhost:8080"
echo "🔧 API Status: http://localhost:8080/admin/status"
echo ""
echo "Try these actions:"
echo "1. Open the dashboard in your browser"
echo "2. Click 'Test Traffic' to see load balancing"
echo "3. Change version to 'v2.0' and click 'Deploy'"
echo "4. Watch the rolling deployment process"
echo ""
echo "To stop: ./cleanup.sh"
