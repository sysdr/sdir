#!/bin/bash

echo "🏗️  Building Two-Phase Commit Demo..."

# Check dependencies
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed."; exit 1; }

# Clean up any existing containers
echo "🧹 Cleaning up existing containers..."
docker-compose down -v 2>/dev/null || true

# Build and start services
echo "🚀 Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Check service health
echo "🔍 Checking service health..."
services=("coordinator:8000" "payment-service:8001" "inventory-service:8002" "shipping-service:8003")

for service in "${services[@]}"; do
    IFS=':' read -r name port <<< "$service"
    if curl -s "http://localhost:$port/health" > /dev/null; then
        echo "✅ $name is healthy"
    else
        echo "❌ $name is not responding"
    fi
done

echo ""
echo "🎉 Two-Phase Commit Demo is ready!"
echo ""
echo "📱 Access points:"
echo "  🌐 Web UI:           http://localhost:3000"
echo "  🎯 Coordinator API:  http://localhost:8000"
echo "  💳 Payment Service:  http://localhost:8001"
echo "  📦 Inventory Service: http://localhost:8002"
echo "  🚚 Shipping Service: http://localhost:8003"
echo "  📊 Prometheus:       http://localhost:9090"
echo "  📈 Grafana:          http://localhost:3001 (admin/admin)"
echo ""
echo "🧪 Test commands:"
echo "  ./scripts/test_scenarios.sh"
echo "  ./scripts/chaos_testing.sh"
echo ""
echo "📋 Monitor logs:"
echo "  docker-compose logs -f coordinator"
echo "  docker-compose logs -f payment-service"
echo ""
echo "🛑 To stop:"
echo "  docker-compose down"
