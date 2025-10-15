#!/bin/bash

set -e

echo "🚀 Starting Graceful Degradation Demo..."

# Install dependencies if not using Docker
if [[ "$1" != "--docker" ]]; then
    echo "📦 Installing dependencies..."
    npm install
    
    echo "🏗️ Starting services locally..."
    
    # Start services in background
    PORT=3001 node src/product-service.js &
    PRODUCT_PID=$!
    
    PORT=3002 node src/payment-service.js &
    PAYMENT_PID=$!
    
    PORT=3003 node src/inventory-service.js &
    INVENTORY_PID=$!
    
    # Start gateway
    sleep 3
    PORT=3000 node src/gateway.js &
    GATEWAY_PID=$!
    
    echo "⏳ Waiting for services to start..."
    sleep 5
    
    echo "✅ Services started!"
    echo "🌐 Dashboard: http://localhost:3000"
    echo "📊 API Gateway: http://localhost:3000"
    echo "🔧 Product Service: http://localhost:3001"
    echo "💳 Payment Service: http://localhost:3002"
    echo "📦 Inventory Service: http://localhost:3003"
    
    # Save PIDs for cleanup
    echo "$PRODUCT_PID $PAYMENT_PID $INVENTORY_PID $GATEWAY_PID" > .demo_pids
    
    echo "🧪 Running tests..."
    sleep 2
    node tests/degradation-tests.js
    
    echo ""
    echo "🎉 Demo is ready!"
    echo "Open http://localhost:3000 in your browser to see the dashboard"
    echo "Run './cleanup.sh' when done"
    
else
    echo "🐳 Starting with Docker..."
    
    # Build and start with Docker Compose
    docker-compose build
    docker-compose up -d
    
    echo "⏳ Waiting for services to start..."
    sleep 10
    
    echo "✅ Services started!"
    echo "🌐 Dashboard: http://localhost:3000"
    
    echo "🧪 Running tests..."
    sleep 5
    docker-compose exec gateway node tests/degradation-tests.js
    
    echo ""
    echo "🎉 Demo is ready!"
    echo "Open http://localhost:3000 in your browser"
    echo "Run './cleanup.sh' when done"
fi
