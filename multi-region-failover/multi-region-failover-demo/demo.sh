#!/bin/bash

set -e

echo "🌍 Multi-Region Failover Demo Setup"
echo "=================================="

# Check dependencies
echo "📋 Checking dependencies..."
command -v docker >/dev/null 2>&1 || { echo "❌ Docker not found. Please install Docker."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose not found. Please install Docker Compose."; exit 1; }

echo "✅ All dependencies found!"

# Create logs directory
mkdir -p logs

# Install Node.js dependencies
echo "📦 Installing dependencies..."
npm install

# Build and start services
echo "🚀 Building and starting services..."
docker-compose build
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Check if services are running
echo "🔍 Checking service health..."
for i in {1..30}; do
  if curl -s http://localhost:3000/api/health > /dev/null; then
    echo "✅ Application is ready!"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "❌ Services failed to start properly"
    docker-compose logs
    exit 1
  fi
  sleep 2
done

# Run tests
echo "🧪 Running tests..."
npm test

echo ""
echo "🎉 Demo Setup Complete!"
echo "======================="
echo ""
echo "🌐 Access the dashboard: http://localhost:3000"
echo "🔧 API endpoint: http://localhost:3000/api/status"
echo "📊 Redis (if needed): localhost:6379"
echo ""
echo "📝 Available commands:"
echo "  • docker-compose logs -f    - View live logs"
echo "  • ./cleanup.sh              - Stop and cleanup"
echo "  • npm test                  - Run test suite"
echo ""
echo "🔥 Try these demo scenarios:"
echo "  1. Open the dashboard in your browser"
echo "  2. Click 'Chaos Test' to simulate random failures"
echo "  3. Watch the automatic failover process"
echo "  4. Use 'Recover All' to restore all regions"
echo "  5. Manually simulate failures on specific regions"
echo ""
echo "Happy testing! 🚀"
