#!/bin/bash

echo "🚀 Starting SRE Core Principles Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose > /dev/null 2>&1; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose and try again."
    exit 1
fi

echo "📦 Building and starting services..."

# Build and start all services
docker-compose up --build -d

echo "⏳ Waiting for services to be ready..."

# Wait for services to be healthy
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if docker-compose ps | grep -q "unhealthy\|starting"; then
        echo "   Waiting for services... (attempt $((attempt + 1))/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    else
        break
    fi
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ Services did not start properly. Checking logs..."
    docker-compose logs
    exit 1
fi

echo "✅ Services are ready!"

# Display access information
echo ""
echo "🌐 SRE Dashboard: http://localhost:3000"
echo "🔧 Backend API: http://localhost:8080"
echo "📊 Redis: localhost:6379"
echo ""

# Run basic tests
echo "🧪 Running basic functionality tests..."

# Test backend health
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
    echo "✅ Backend health check passed"
else
    echo "❌ Backend health check failed"
fi

# Test API endpoints
if curl -f http://localhost:8080/api/dashboard/stats > /dev/null 2>&1; then
    echo "✅ Dashboard API working"
else
    echo "❌ Dashboard API failed"
fi

# Test frontend
if curl -f http://localhost:3000 > /dev/null 2>&1; then
    echo "✅ Frontend accessible"
else
    echo "❌ Frontend not accessible"
fi

echo ""
echo "🎯 Demo Features to Explore:"
echo "   • Real-time SLO/SLI tracking"
echo "   • Error budget monitoring with burn rate alerts"
echo "   • Service health dashboard"
echo "   • Incident timeline and management"
echo "   • Automated alerting system"
echo ""
echo "📚 Learning Path:"
echo "   1. Observe SLO metrics and error budget consumption"
echo "   2. Monitor service health status changes"
echo "   3. Review incident response workflows"
echo "   4. Understand alerting thresholds and escalation"
echo ""
echo "🔗 Quick Links:"
echo "   • Dashboard: http://localhost:3000"
echo "   • API Docs: http://localhost:8080/api"
echo "   • Logs: docker-compose logs -f"
echo ""
echo "✨ Demo is running! Press Ctrl+C to stop or run ./cleanup.sh"
