#!/bin/bash

echo "🚀 Starting Health Check Demo..."

# Build and start services
echo "📦 Building services..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 30

# Check if all services are running
echo "🔍 Checking service health..."
for port in 3000 4000 5001 5002 5003; do
    if curl -f -s "http://localhost:$port/health/shallow" > /dev/null 2>&1 || \
       curl -f -s "http://localhost:$port" > /dev/null 2>&1; then
        echo "✅ Service on port $port is responding"
    else
        echo "❌ Service on port $port is not responding"
    fi
done

echo ""
echo "🎉 Health Check Demo is ready!"
echo ""
echo "🌐 Access points:"
echo "   • Dashboard: http://localhost:3000"
echo "   • Health Monitor API: http://localhost:4000"
echo "   • User Service: http://localhost:5001"
echo "   • Payment Service: http://localhost:5002"  
echo "   • Order Service: http://localhost:5003"
echo ""
echo "🧪 Test commands:"
echo "   • Run tests: docker run --rm -v \$(pwd)/tests:/tests --network host python:3.11-slim bash -c 'cd /tests && pip install -r requirements.txt && python test_health_checks.py'"
echo "   • View logs: docker-compose logs -f"
echo "   • Stop demo: ./cleanup.sh"
echo ""
echo "💡 Demo features:"
echo "   • Real-time health monitoring"
echo "   • Shallow vs deep health checks"
echo "   • Failure injection (DB, latency, memory)"
echo "   • Health status visualization"
echo "   • Automated recovery simulation"
