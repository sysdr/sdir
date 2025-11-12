#!/bin/bash

cd fraud-detection-demo

echo "✅ Project structure created!"
echo ""
echo "🚀 Building and starting services..."

# Build and start
docker-compose build
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 25

echo ""
echo "🧪 Running tests..."
./tests/test_system.sh

echo ""
echo "✅ Fraud Detection System is running!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔌 API: http://localhost:3001"
echo ""
echo "💡 Try these actions:"
echo "  1. Open http://localhost:3000 in your browser"
echo "  2. Click 'Submit Normal Transaction' to see approved transactions"
echo "  3. Click 'Submit Suspicious Transaction' to trigger fraud detection"
echo "  4. Watch real-time risk scoring and decisions"
echo ""
echo "🔍 View logs:"
echo "  docker-compose logs -f transaction-service"
echo "  docker-compose logs -f feature-service"
echo "  docker-compose logs -f risk-service"
echo ""
echo "📈 System demonstrates:"
echo "  • Real-time transaction processing via Kafka"
echo "  • Feature extraction (velocity, geo, device, graph)"
echo "  • Hybrid scoring (Rules Engine + ML)"
echo "  • Sub-150ms decision latency"
echo "  • WebSocket updates to dashboard"
