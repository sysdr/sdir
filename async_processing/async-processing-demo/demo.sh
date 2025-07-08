#!/bin/bash

# Async Processing Demo - Main Demo Script
set -e

echo "🚀 Starting Async Processing Demo Setup..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ Docker Compose is not installed. Please install it and try again."
    exit 1
fi

echo "✅ Docker and Docker Compose are available"

# Build and start services
echo "🏗️  Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Check service health
echo "🔍 Checking service health..."

# Check Redis
if docker-compose exec -T redis redis-cli ping >/dev/null 2>&1; then
    echo "✅ Redis is healthy"
else
    echo "❌ Redis is not responding"
fi

# Check PostgreSQL
if docker-compose exec -T postgres pg_isready -U demo >/dev/null 2>&1; then
    echo "✅ PostgreSQL is healthy"
else
    echo "❌ PostgreSQL is not responding"
fi

# Check main application
if curl -s http://localhost:8000/ >/dev/null; then
    echo "✅ Main application is responding"
else
    echo "❌ Main application is not responding"
fi

# Check Flower (Celery monitoring)
if curl -s http://localhost:5555/ >/dev/null; then
    echo "✅ Flower (Celery monitor) is responding"
else
    echo "❌ Flower is not responding"
fi

# Run tests
echo "🧪 Running automated tests..."
docker-compose exec -T app python -m pytest tests/ -v || echo "⚠️  Some tests may have failed, but demo should still work"

# Display access information
echo ""
echo "🎉 Demo is ready!"
echo ""
echo "📱 Access Points:"
echo "   Main Demo:     http://localhost:8000"
echo "   Celery Monitor: http://localhost:5555 (Flower)"
echo "   Redis:         localhost:6379"
echo "   PostgreSQL:    localhost:5432 (user: demo, password: demo123)"
echo ""
echo "🔧 Demo Features:"
echo "   ✨ Create image processing tasks"
echo "   ✨ Send email tasks"
echo "   ✨ Generate reports"
echo "   ✨ Run heavy computations"
echo "   ✨ Monitor queue and task status in real-time"
echo "   ✨ View system metrics and performance"
echo ""
echo "📊 Monitoring:"
echo "   • Real-time task status updates"
echo "   • Queue depth and worker statistics"
echo "   • Task completion metrics"
echo "   • Error handling and retry mechanisms"
echo ""
echo "🧪 Testing:"
echo "   Run: docker-compose exec app python -m pytest tests/ -v"
echo ""
echo "📝 Logs:"
echo "   View all: docker-compose logs"
echo "   View app: docker-compose logs app"
echo "   View worker: docker-compose logs worker"
echo ""
echo "🛑 To stop: ./cleanup.sh"
echo ""
