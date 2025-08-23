#!/bin/bash

echo "🚀 Starting Self-Healing Systems Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Install dependencies for all services
echo "📦 Installing dependencies..."
cd services/user-service && npm install --silent
cd ../order-service && npm install --silent
cd ../payment-service && npm install --silent
cd ../../healing-controller && npm install --silent
cd ../dashboard && npm install --silent
cd ..

echo "🏗️ Building and starting services..."
docker-compose up --build -d

echo "⏳ Waiting for services to start..."
sleep 30

echo "🔍 Checking service health..."
for i in {1..12}; do
    if curl -sf http://localhost:3004/health > /dev/null; then
        echo "✅ Healing controller is ready"
        break
    fi
    echo "⏳ Waiting for healing controller... ($i/12)"
    sleep 5
done

echo ""
echo "🎉 Self-Healing Systems Demo is ready!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🏥 Controller: http://localhost:3004"
echo "👤 User Service: http://localhost:3001"
echo "📦 Order Service: http://localhost:3002"
echo "💳 Payment Service: http://localhost:3003"
echo ""
echo "🧪 Test Instructions:"
echo "1. Open the dashboard at http://localhost:3000"
echo "2. Click 'Memory Leak' button on any service"
echo "3. Watch the memory usage increase"
echo "4. Observe automatic healing when it reaches critical levels"
echo "5. Check the healing history for recovery details"
echo ""
echo "🛑 To stop: ./cleanup.sh"
