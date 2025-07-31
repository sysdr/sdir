#!/bin/bash
set -e

echo "🚀 Starting Push Notification System Demo..."

# Install dependencies if not in Docker
if [ ! -f /.dockerenv ]; then
    echo "📦 Installing system dependencies..."
    if command -v apt-get &> /dev/null; then
        sudo apt-get update
        sudo apt-get install -y docker.io docker-compose-plugin curl jq
    elif command -v yum &> /dev/null; then
        sudo yum install -y docker docker-compose curl jq
    fi
fi

# Build and start services
echo "🔨 Building services..."
docker compose build

echo "🚀 Starting services..."
docker compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Health checks
echo "🏥 Checking service health..."
for i in {1..30}; do
    if curl -s http://localhost:3001/health > /dev/null && \
       curl -s http://localhost:3002/health > /dev/null && \
       curl -s http://localhost:3000 > /dev/null; then
        echo "✅ All services are healthy!"
        break
    fi
    echo "⏳ Waiting for services... ($i/30)"
    sleep 2
done

# Run tests
echo "🧪 Running integration tests..."
sleep 5
npm test

echo "✅ Demo is ready!"
echo ""
echo "🌐 Access Points:"
echo "  Dashboard:        http://localhost:3000"
echo "  WebSocket API:    ws://localhost:3001"
echo "  Notification API: http://localhost:3002"
echo "  Redis Insight:    http://localhost:8001"
echo ""
echo "🎯 Demo Steps:"
echo "1. Open dashboard: http://localhost:3000"
echo "2. Click 'Connect Devices' to simulate 1000 clients"
echo "3. Send notifications using the dashboard"
echo "4. Watch real-time metrics and delivery status"
echo "5. Test failure scenarios with 'Disconnect Random Clients'"
echo ""
echo "📊 Load Testing:"
echo "  docker compose exec tests npm run load-test"
echo ""
