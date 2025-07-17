#!/bin/bash

echo "🚀 Starting Predictive Scaling Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start the application
echo "📦 Building Docker image..."
docker-compose build

echo "🏃 Starting services..."
docker-compose up -d

# Wait for service to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Health check
echo "🔍 Checking service health..."
for i in {1..30}; do
    if curl -f http://localhost:5000/ > /dev/null 2>&1; then
        echo "✅ Service is healthy!"
        break
    fi
    echo "⏳ Waiting for service... ($i/30)"
    sleep 2
done

echo ""
echo "🎉 Predictive Scaling Demo is ready!"
echo ""
echo "📊 Dashboard: http://localhost:5000"
echo ""
echo "🧪 Demo Steps:"
echo "1. Open http://localhost:5000 in your browser"
echo "2. Click 'Refresh Data' to load historical patterns"
echo "3. Click 'Simulate Traffic Spike' to test predictive scaling"
echo "4. Click 'Refresh Data' again to see the spike impact on predictions"
echo "5. Observe how the system predicts and scales proactively"
echo ""
echo "📈 Key Features:"
echo "- Real-time traffic prediction using ensemble models"
echo "- Confidence-based scaling decisions"
echo "- Cost optimization calculations"
echo "- Interactive visualization dashboard"
echo "- Live traffic spike simulation with model retraining"
echo ""
echo "🔧 To stop the demo, run: ./cleanup.sh"
