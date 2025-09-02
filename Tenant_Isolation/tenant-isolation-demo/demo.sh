#!/bin/bash

echo "🚀 Starting Tenant Isolation Demo..."

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed."; exit 1; }

# Build and start services
echo "🏗️ Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Check if services are healthy
echo "🔍 Checking service health..."
if curl -f http://localhost:3001/health >/dev/null 2>&1; then
    echo "✅ Backend service is healthy"
else
    echo "❌ Backend service is not responding"
    docker-compose logs backend
    exit 1
fi

if curl -f http://localhost:3000 >/dev/null 2>&1; then
    echo "✅ Frontend service is healthy"
else
    echo "❌ Frontend service is not responding"
    docker-compose logs frontend
    exit 1
fi

# Run isolation tests
echo "🧪 Running isolation tests..."
cd tests
node isolation-tests.js

echo ""
echo "🎉 Demo is ready!"
echo ""
echo "📋 Access Points:"
echo "   🌐 Frontend Dashboard: http://localhost:3000"
echo "   🔧 API Backend: http://localhost:3001"
echo "   📊 Health Check: http://localhost:3001/health"
echo ""
echo "🔑 Demo Tenant API Keys:"
echo "   • ACME Corp: acme-key-123"
echo "   • Startup Inc: startup-key-456"
echo "   • Enterprise Ltd: enterprise-key-789"
echo ""
echo "🧪 Test Scenarios:"
echo "   1. Switch between tenants to see data isolation"
echo "   2. Create tasks in different tenants"
echo "   3. Test rate limiting with 'Test Rate Limit' button"
echo "   4. Monitor metrics for resource isolation"
echo ""
echo "📝 Manual API Testing:"
echo "   curl -H 'X-API-Key: acme-key-123' http://localhost:3001/api/tasks"
echo "   curl -H 'X-API-Key: startup-key-456' http://localhost:3001/api/metrics"
echo ""
