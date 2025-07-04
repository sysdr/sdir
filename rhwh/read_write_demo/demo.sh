#!/bin/bash

echo "🚀 Starting Read-Heavy vs Write-Heavy Systems Demo..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Build and start services
echo "🔨 Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Check if services are running
if docker-compose ps | grep -q "Up"; then
    echo "✅ Services started successfully!"
    echo ""
    echo "🌐 Demo URL: http://localhost:5000"
    echo "📊 Redis: localhost:6379"
    echo "🗄️  PostgreSQL: localhost:5432"
    echo ""
    echo "🎯 Try these experiments:"
    echo "   1. Toggle between Read-Heavy and Write-Heavy modes"
    echo "   2. Enable/disable caching and observe performance"
    echo "   3. Run load tests with different configurations"
    echo "   4. Compare metrics between optimization strategies"
    echo ""
    echo "📝 Check logs: docker-compose logs -f"
    echo "🛑 Stop demo: ./cleanup.sh"
else
    echo "❌ Failed to start services. Check logs:"
    docker-compose logs
fi
