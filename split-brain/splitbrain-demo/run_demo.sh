#!/bin/bash

echo "🚀 Split-Brain Prevention Demo Setup"
echo "======================================"

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

echo "📦 Building Docker image..."
docker-compose build

echo "🔧 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to start..."
sleep 10

echo "🧪 Running tests..."
python test_demo.py

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Demo is ready!"
    echo "🌐 Open your browser and navigate to: http://localhost:8000"
    echo ""
    echo "📋 Available scenarios:"
    echo "  1. Click 'Create Cluster' to initialize 5 nodes"
    echo "  2. Use scenario buttons to test different partition types"
    echo "  3. Watch the real-time visualization of consensus behavior"
    echo "  4. Observe how quorum prevents split-brain scenarios"
    echo ""
    echo "🔧 To stop the demo: docker-compose down"
    echo "📋 To view logs: docker-compose logs -f"
else
    echo "❌ Tests failed. Check the logs for issues."
    docker-compose logs
fi
