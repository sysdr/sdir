#!/bin/bash

echo "🚀 Starting Redundancy Patterns Demo..."

# Install dependencies
echo "📦 Installing Node.js dependencies..."
npm install

# Build and start with Docker
echo "🐳 Building and starting services with Docker..."
docker-compose up --build -d

echo "⏳ Waiting for services to start..."
sleep 10

# Check if services are running
echo "🔍 Checking service health..."
for port in 3001 3002 3003 3004; do
    if curl -s "http://localhost:$port/health" > /dev/null; then
        echo "✅ Service on port $port is healthy"
    else
        echo "❌ Service on port $port is not responding"
    fi
done

echo "🔄 Checking load balancer..."
if curl -s "http://localhost:3000/api/status" > /dev/null; then
    echo "✅ Load balancer is running"
else
    echo "❌ Load balancer is not responding"
fi

echo ""
echo "🎉 Demo is ready!"
echo "📊 Dashboard: http://localhost:3000"
echo "🔄 Load Balancer API: http://localhost:3000/api/status"
echo ""
echo "🧪 To run tests:"
echo "npm test"
echo ""
echo "📝 Available endpoints:"
echo "  GET  /api/data       - Get data (load balanced)"
echo "  GET  /api/status     - System status"
echo "  POST /api/services/:port/fail    - Fail a service"
echo "  POST /api/services/:port/recover - Recover a service"
echo ""
echo "🔧 To view logs:"
echo "docker-compose logs -f"
