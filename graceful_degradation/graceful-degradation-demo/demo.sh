#!/bin/bash

echo "🚀 Starting Graceful Degradation Demo..."

# Build and start services
echo "Building Docker containers..."
docker-compose build

echo "Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to initialize..."
sleep 10

# Check if services are running
if curl -s http://localhost:8080/api/status > /dev/null; then
    echo "✅ Demo is ready!"
    echo ""
    echo "🌐 Open your browser to: http://localhost:8080"
    echo "📊 System status API: http://localhost:8080/api/status"
    echo "📈 Metrics endpoint: http://localhost:8080/metrics"
    echo ""
    echo "🎮 Try these test scenarios:"
    echo "  1. Click 'Light Load' to see normal operation"
    echo "  2. Click 'Heavy Load' to trigger feature degradation"
    echo "  3. Click 'Extreme Load' to see circuit breakers activate"
    echo "  4. Use 'Test Recommendations' and 'Test Reviews' to see fallback behaviors"
    echo ""
    echo "📋 Watch the logs in real-time to see graceful degradation in action!"
    echo ""
    echo "To stop the demo, run: ./cleanup.sh"
else
    echo "❌ Demo failed to start. Check the logs:"
    docker-compose logs
fi
