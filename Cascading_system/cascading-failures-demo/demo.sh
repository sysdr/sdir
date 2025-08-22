#!/bin/bash

set -e

echo "🚀 Starting Cascading Failures Demo..."

# Function to wait for service
wait_for_service() {
    echo "⏳ Waiting for $1 to be ready..."
    for i in {1..30}; do
        if curl -s "$2" > /dev/null 2>&1; then
            echo "✅ $1 is ready"
            return 0
        fi
        sleep 2
    done
    echo "❌ $1 failed to start"
    exit 1
}

# Build and start services
echo "📦 Building Docker images..."
docker-compose build

echo "🎬 Starting services..."
docker-compose up -d

# Wait for all services
wait_for_service "Auth Service" "http://localhost:8001/health"
wait_for_service "User Service" "http://localhost:8002/health"
wait_for_service "Order Service" "http://localhost:8003/health"
wait_for_service "Dashboard" "http://localhost:8080"

echo ""
echo "🎉 Demo is ready!"
echo ""
echo "📊 Access points:"
echo "  • Main Dashboard: http://localhost:8080"
echo "  • Auth Service:   http://localhost:8001/health"
echo "  • User Service:   http://localhost:8002/health" 
echo "  • Order Service:  http://localhost:8003/health"
echo ""
echo "🧪 Demo scenarios:"
echo "  1. Open http://localhost:8080 in your browser"
echo "  2. Click 'Generate Load' to see normal operation"
echo "  3. Click 'Trigger Auth Failure' to start cascade"
echo "  4. Watch circuit breakers open across services"
echo "  5. Click 'Recover All Services' to see healing"
echo ""
echo "🔍 Testing cascade detection:"
echo "  • Green services = healthy with closed circuits"
echo "  • Yellow services = degraded with half-open circuits"  
echo "  • Red services = failed with open circuits"
echo ""
echo "📈 Advanced testing:"
echo "curl -X POST http://localhost:8003/order/create -H 'Content-Type: application/json' -d '{\"user_id\":\"test\",\"items\":[\"item1\"],\"total\":99.99}'"
echo ""
echo "🧪 Run tests:"
echo "docker-compose exec order-service python -m pytest tests/ -v"
echo ""
echo "🛑 To stop demo: ./cleanup.sh"
