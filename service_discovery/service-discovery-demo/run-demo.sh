#!/bin/bash

echo "🚀 Starting Service Discovery Demo"
echo "================================"

# Build and start all services
echo "📦 Building Docker images..."
docker-compose build

echo "🔄 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 30

echo "✅ Demo is ready!"
echo ""
echo "🌐 Access Points:"
echo "  • Consul UI:        http://localhost:8500"
echo "  • API Gateway:      http://localhost:8000"
echo "  • Web Dashboard:    http://localhost:3000"
echo "  • User Service 1:   http://localhost:8001"
echo "  • User Service 2:   http://localhost:8002"
echo "  • Order Service:    http://localhost:8003"
echo ""
echo "🧪 Test Commands:"
echo "  curl http://localhost:8000/api/users"
echo "  curl http://localhost:8000/api/orders/1"
echo "  curl http://localhost:8000/api/discovery/services"
echo ""
echo "📊 Monitor logs with: docker-compose logs -f"
echo "🛑 Stop demo with: docker-compose down"
