#!/bin/bash

echo "🚀 Starting Event-Driven Architecture Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start all services
echo "📦 Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 30

# Check service health
echo "🏥 Checking service health..."
for port in 3001 3002 3003 3004 3005; do
    if curl -f http://localhost:$port/health > /dev/null 2>&1; then
        echo "✅ Service on port $port is healthy"
    else
        echo "❌ Service on port $port is not responding"
    fi
done

echo ""
echo "🎉 Event-Driven Architecture Demo is ready!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔗 API Endpoints:"
echo "   - Orders: http://localhost:3001"
echo "   - Inventory: http://localhost:3002"
echo "   - Payments: http://localhost:3003"
echo "   - Notifications: http://localhost:3004"
echo "   - Analytics: http://localhost:3005"
echo ""
echo "🧪 Try these demo scenarios:"
echo "1. Create orders to see Event Sourcing in action"
echo "2. Check inventory to see CQRS read/write separation"
echo "3. Process payments to see Pub/Sub messaging"
echo "4. Trigger event storm to see anti-pattern effects"
echo ""
echo "📝 To view logs: docker-compose logs -f [service-name]"
echo "🛑 To stop: ./cleanup.sh"
