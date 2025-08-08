#!/bin/bash

echo "🚀 Starting Resilience Testing Demo..."



# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is required but not installed"
    exit 1
fi

echo "✅ Prerequisites check passed"

# Install dependencies and build
echo "📦 Installing dependencies..."
npm install

echo "🔨 Building and starting services..."
docker-compose up --build -d

echo "⏳ Waiting for services to be ready..."
sleep 30

# Verify services are running
echo "🔍 Verifying service health..."
for port in 3001 3002 3003 3004 3000 9090; do
    if curl -f http://localhost:$port/health &>/dev/null || curl -f http://localhost:$port &>/dev/null; then
        echo "✅ Service on port $port is healthy"
    else
        echo "⚠️  Service on port $port may still be starting..."
    fi
done

echo ""
echo "🎉 Resilience Testing Demo is ready!"
echo ""
echo "🌐 Access Points:"
echo "   Dashboard:        http://localhost:3000"
echo "   Web API:          http://localhost:3001"
echo "   Database Service: http://localhost:3002"
echo "   Cache Service:    http://localhost:3003"
echo "   Chaos Controller: http://localhost:3004"
echo "   Prometheus:       http://localhost:9090"
echo ""
echo "🧪 Demo Steps:"
echo "1. Open the dashboard at http://localhost:3000"
echo "2. Observe healthy services in the status grid"
echo "3. Run load tests to establish baseline performance"
echo "4. Click chaos experiment buttons to inject failures"
echo "5. Watch real-time response time charts during chaos"
echo "6. Observe circuit breaker behavior and recovery"
echo "7. Check Prometheus metrics at http://localhost:9090"
echo ""
echo "🔬 Chaos Experiments Available:"
echo "   • Network Latency (1s delay to database)"
echo "   • Error Injection (30% error rate)"
echo "   • CPU Spike (high CPU load)"
echo "   • Cache Chaos (multiple failure types)"
echo ""
echo "🧪 Run tests with: npm test"
echo "🛑 Stop demo with: ./cleanup.sh"
