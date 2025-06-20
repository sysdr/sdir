#!/bin/bash

echo "🔍 Verifying CQRS Demo Setup..."
echo "================================"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

echo "✅ Docker is running"

# Check if services are up
echo "🐳 Checking Docker services..."

services=("command-db" "query-db" "event-bus" "command-service" "query-service" "web-ui")

for service in "${services[@]}"; do
    if docker-compose ps | grep -q "$service.*Up"; then
        echo "✅ $service is running"
    else
        echo "❌ $service is not running"
    fi
done

# Test API endpoints
echo "🌐 Testing API endpoints..."

# Command service
if curl -s -f http://localhost:8001/health > /dev/null; then
    echo "✅ Command service API is responding"
else
    echo "❌ Command service API is not responding"
fi

# Query service
if curl -s -f http://localhost:8002/health > /dev/null; then
    echo "✅ Query service API is responding"
else
    echo "❌ Query service API is not responding"
fi

# Web UI
if curl -s -f http://localhost:3000 > /dev/null; then
    echo "✅ Web UI is accessible"
else
    echo "❌ Web UI is not accessible"
fi

echo ""
echo "🎯 Access Points:"
echo "   🌐 Web UI: http://localhost:3000"
echo "   ⚡ Command API: http://localhost:8001/docs"
echo "   🔍 Query API: http://localhost:8002/docs"
echo ""
echo "🧪 Run tests with: python3 scripts/test_cqrs.py"
