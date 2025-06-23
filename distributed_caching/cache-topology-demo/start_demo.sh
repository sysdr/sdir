#!/bin/bash

echo "🚀 Starting Distributed Cache Topology Demonstrator..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Build and start services
echo "🔨 Building Docker images..."
docker-compose build

echo "🏃 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check if services are healthy
if docker-compose ps | grep -q "unhealthy\|Exit"; then
    echo "❌ Some services failed to start properly"
    docker-compose logs
    exit 1
fi

echo "✅ All services are running!"
echo ""
echo "🌐 Access points:"
echo "   Web Interface: http://localhost:5000"
echo "   Redis: localhost:6379"
echo ""
echo "🧪 Run tests:"
echo "   python tests/test_cache_patterns.py"
echo ""
echo "📊 To view logs:"
echo "   docker-compose logs -f cache-demo"
echo ""
echo "🛑 To stop:"
echo "   docker-compose down"
