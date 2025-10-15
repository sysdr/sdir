#!/bin/bash

set -e

echo "🚀 Starting Bounded Contexts Demo..."

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed."
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is required but not installed."
    exit 1
fi

# Install dependencies and build
echo "📦 Installing dependencies..."
cd user-service && npm install --silent && cd ..
cd product-service && npm install --silent && cd ..
cd order-service && npm install --silent && cd ..
cd payment-service && npm install --silent && cd ..
cd dashboard && npm install --silent && cd ..

# Build and start services
echo "🐳 Building Docker images..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services
echo "⏳ Waiting for services to be ready..."
timeout=60
counter=0

while [ $counter -lt $timeout ]; do
    if curl -s http://localhost:3000/api/health > /dev/null 2>&1; then
        echo "✅ Services are ready!"
        break
    fi
    sleep 2
    counter=$((counter + 2))
    echo "Waiting... ($counter/$timeout seconds)"
done

if [ $counter -ge $timeout ]; then
    echo "❌ Services failed to start within $timeout seconds"
    echo "🔍 Checking logs..."
    docker-compose logs --tail=10
    exit 1
fi

# Run tests
echo "🧪 Running integration tests..."
./run-tests.sh

echo ""
echo "🎉 Bounded Contexts Demo is ready!"
echo ""
echo "📊 Dashboard:     http://localhost:3000"
echo "🧑 User Service:   http://localhost:3001/health"
echo "📦 Product Service: http://localhost:3002/health"
echo "📋 Order Service:   http://localhost:3003/health"
echo "💳 Payment Service: http://localhost:3004/health"
echo ""
echo "🔗 Key Demo Features:"
echo "   • Each context has its own database and domain logic"
echo "   • Cross-context communication via APIs (not database joins)"
echo "   • Context isolation - changes in one don't affect others"
echo "   • Anti-corruption layers prevent external models from leaking"
echo ""
echo "🧪 Try This:"
echo "   1. Update a product price in the dashboard"
echo "   2. Notice how only Product Context is affected"
echo "   3. Create users and orders to see cross-context communication"
echo "   4. Watch the activity log for real-time isolation demonstration"
echo ""
echo "🛑 To stop: ./cleanup.sh"
