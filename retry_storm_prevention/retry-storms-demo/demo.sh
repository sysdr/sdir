#!/bin/bash

echo "🚀 Starting Retry Storms Prevention Demo..."

# Check if Docker is running
if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose >/dev/null 2>&1; then
    echo "❌ Docker Compose not found. Please install Docker Compose."
    exit 1
fi

echo "📦 Building and starting services..."
docker-compose up --build -d

echo "⏳ Waiting for services to be ready..."
sleep 30

# Health checks
echo "🔍 Checking service health..."
services=("http://localhost:8000/health" "http://localhost:8001/health")
for service in "${services[@]}"; do
    for i in {1..10}; do
        if curl -f -s "$service" >/dev/null; then
            echo "✅ $service is healthy"
            break
        else
            echo "⏳ Waiting for $service..."
            sleep 3
        fi
    done
done

echo ""
echo "🎉 Demo is ready!"
echo ""
echo "📱 Access points:"
echo "   Dashboard: http://localhost:3000"
echo "   Gateway API: http://localhost:8000"
echo "   Backend API: http://localhost:8001"
echo "   Prometheus: http://localhost:9090"
echo ""
echo "🧪 Quick test scenarios:"
echo ""
echo "1. 📈 Normal Operation:"
echo "   - Open dashboard at http://localhost:3000"
echo "   - Start load test with default settings"
echo "   - Observe normal success rates and low latency"
echo ""
echo "2. ⚠️  Create Retry Storm:"
echo "   - Set backend failure rate to 0.5 (50%)"
echo "   - Set backend latency to 2000ms"
echo "   - Disable circuit breaker (set threshold to 100)"
echo "   - Start high load test (50 RPS, 10 clients)"
echo "   - Watch success rate drop and latency spike"
echo ""
echo "3. 🛡️  Prevent with Circuit Breaker:"
echo "   - Keep backend failure rate at 0.5"
echo "   - Enable circuit breaker (threshold: 5)"
echo "   - Start load test"
echo "   - Watch circuit breaker open and protect system"
echo ""
echo "4. 🔄 Test Recovery:"
echo "   - Set backend failure rate back to 0.0"
echo "   - Watch circuit breaker transition to half-open then closed"
echo "   - Observe system recovery"
echo ""
echo "📊 Monitor the following metrics:"
echo "   - Success rate trends"
echo "   - Average latency"
echo "   - Circuit breaker state changes"
echo "   - Request retry patterns"
echo ""
echo "🔧 Stop demo:"
echo "   ./cleanup.sh"
