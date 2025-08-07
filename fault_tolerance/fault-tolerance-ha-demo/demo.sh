#!/bin/bash

echo "🚀 Starting Fault Tolerance vs High Availability Demo"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

echo "📦 Installing frontend dependencies..."
cd frontend && npm install --force && cd ..

echo "📦 Installing service dependencies..."
cd services/payment && npm install --force && cd ../..
cd services/user && npm install --force && cd ../..
cd services/gateway && npm install --force && cd ../..

echo "📦 Installing test dependencies..."
cd tests && npm install --force && cd ..

echo "🐳 Building and starting Docker containers..."
docker-compose up --build -d

echo "⏳ Waiting for services to be ready..."
sleep 15

echo "🧪 Running system tests..."
cd tests && npm test

echo "🔍 Verifying dashboard functionality..."
echo "   Checking if dashboard is accessible..."
if curl -s http://localhost:80 > /dev/null; then
    echo "   ✅ Dashboard is accessible at http://localhost:80"
else
    echo "   ⚠️  Dashboard may still be starting up..."
fi

echo "   Checking if API gateway is responding..."
if curl -s http://localhost:8080/api/metrics > /dev/null; then
    echo "   ✅ API gateway is responding"
else
    echo "   ⚠️  API gateway may still be starting up..."
fi

echo "🎉 Demo is ready!"
echo ""
echo "🌐 Access the demo at:"
echo "   Dashboard: http://localhost:80"
echo "   Direct Frontend: http://localhost:3000"
echo "   API Gateway: http://localhost:8080/api/metrics"
echo ""
echo "🎮 Interactive Features:"
echo "   ✅ Verify All - One-click comprehensive system verification"
echo "   🔄 Test Fault Tolerance - Circuit breakers and retry mechanisms"
echo "   ⚖️ Test High Availability - Load balancer failover testing"
echo "   🔄 Reset System - Return all services to healthy state"
echo ""
echo "🔍 What the 'Verify All' button tests:"
echo "   1. Payment Service - Normal transaction processing"
echo "   2. Load Balancing - Request distribution across instances"
echo "   3. Fault Tolerance - Circuit breaker with fallback responses"
echo "   4. High Availability - Failover to healthy instances"
echo "   5. Metrics Collection - Real-time data updates"
echo ""
echo "📊 Real-time Monitoring:"
echo "   • Service health status indicators"
echo "   • Circuit breaker state visualization"
echo "   • Response time metrics"
echo "   • Request history charts"
echo "   • Success rate tracking"
echo ""
echo "🔄 To reset the system: Click 'Reset System' button or run:"
echo "   curl -X POST http://localhost:8080/api/reset"
echo ""
echo "🧪 To run verification manually:"
echo "   curl -X POST http://localhost:8080/api/test/payment-failure"
echo "   curl -X POST http://localhost:8080/api/test/user-service-failure"
echo ""
echo "🛑 To stop the demo:"
echo "   ./cleanup.sh"
echo ""
echo "💡 Pro Tip: Click the 'Verify All' button in the dashboard to run a comprehensive"
echo "   test of all system components in one click!"
