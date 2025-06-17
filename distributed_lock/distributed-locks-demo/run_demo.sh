#!/bin/bash

echo "🔒 Starting Distributed Locking Demo"
echo "===================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Build and start services
echo "🏗️  Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Check if services are healthy
echo "🔍 Checking service health..."
if docker-compose ps | grep -q "Up"; then
    echo "✅ Services are running!"
    echo ""
    echo "🌐 Demo Dashboard: http://localhost:8080"
    echo "📊 Redis: localhost:6379"
    echo ""
    echo "🎯 Demo Features:"
    echo "  • Real-time lock visualization"
    echo "  • Multiple locking mechanisms"
    echo "  • Failure mode simulation"
    echo "  • Fencing token demonstration"
    echo ""
    echo "📝 To stop the demo: docker-compose down"
    echo "🧪 To run tests: docker-compose exec demo-app python -m pytest tests/ -v"
else
    echo "❌ Some services failed to start. Check logs:"
    docker-compose logs
fi
