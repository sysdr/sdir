#!/bin/bash

# Cache Invalidation Strategies Demo Runner
echo "🚀 Starting Cache Invalidation Strategies Demo..."

# Build and start services
echo "🏗️  Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Health check
echo "🔍 Checking service health..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:8000/health | grep -q "healthy"; then
        echo "✅ Services are healthy and ready!"
        break
    fi
    
    attempt=$((attempt + 1))
    echo "⏳ Waiting for services... (attempt $attempt/$max_attempts)"
    sleep 2
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Services failed to start properly"
    docker-compose logs
    exit 1
fi

# Run tests
echo "🧪 Running automated tests..."
docker-compose exec web python -m pytest tests/ -v

echo ""
echo "🎉 Demo is ready!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📱 Web Interface:     http://localhost:8000"
echo "📊 Redis Insight:     http://localhost:8001"
echo "🔍 Health Check:      http://localhost:8000/health"
echo "📈 Metrics API:       http://localhost:8000/api/metrics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 Try these cache invalidation strategies:"
echo "   • TTL-based expiration with jitter"
echo "   • Event-driven invalidation with pub/sub"
echo "   • Lazy invalidation (Facebook TAO style)"
echo "   • Hybrid multi-tier caching (Instagram style)"
echo ""
echo "⚡ Run load tests and simulate cache avalanche scenarios!"
echo "📝 Monitor real-time logs and metrics in the web interface"
echo ""
echo "To stop the demo, run: ./cleanup.sh"
