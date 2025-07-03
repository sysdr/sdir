#!/bin/bash

echo "🚀 Starting Stateless vs Stateful Services Demo..."

# Function to check if command exists
check_command() {
    if ! command -v $1 &> /dev/null; then
        echo "❌ $1 is not installed. Please install it first."
        exit 1
    fi
}

# Check prerequisites
echo "🔍 Checking prerequisites..."
check_command docker
check_command docker-compose

# Build and start services
echo "🏗️  Building and starting services..."
docker-compose build
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Check service health
echo "🏥 Checking service health..."
for port in 8000 8001 8080; do
    if curl -s http://localhost:$port/health > /dev/null 2>&1 || curl -s http://localhost:$port > /dev/null 2>&1; then
        echo "✅ Service on port $port is healthy"
    else
        echo "⚠️  Service on port $port might not be ready yet"
    fi
done

# Run tests
echo "🧪 Running tests..."
docker-compose exec stateless-service python -m pytest tests/test_services.py -v || echo "⚠️  Some tests failed, but demo can continue"

echo ""
echo "🎉 Demo is ready!"
echo ""
echo "📋 Access Points:"
echo "   🌐 Stateless Service: http://localhost:8000"
echo "   🗃️  Stateful Service:  http://localhost:8001"
echo "   📊 Dashboard:         http://localhost:8080"
echo ""
echo "🔧 Testing Commands:"
echo "   Load Test: docker-compose run --rm load-tester python src/load_tester.py"
echo "   View Logs: docker-compose logs -f [service-name]"
echo "   Stop Demo: ./cleanup.sh"
echo ""
echo "🎯 Demo Steps:"
echo "   1. Open both service URLs in separate browser tabs"
echo "   2. Login with different usernames on each service"
echo "   3. Add items to cart and observe behavior"
echo "   4. Open dashboard to compare metrics"
echo "   5. Run load test to see scaling differences"
echo "   6. Restart services (docker-compose restart) and see state persistence differences"
echo ""
