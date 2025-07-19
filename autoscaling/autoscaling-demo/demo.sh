#!/bin/bash
# Quick demo runner

echo "🚀 Starting Autoscaling Demo..."

# Build and start services
docker-compose up --build -d

echo "⏳ Waiting for services to start..."
sleep 10

# Check if services are running
if curl -s http://localhost:3000/api/status > /dev/null; then
    echo "✅ Demo is running!"
    echo ""
    echo "🌐 Web Interface: http://localhost:3000"
    echo "📊 Try different load patterns to see autoscaling in action"
    echo ""
    echo "To stop: docker-compose down"
    echo "To cleanup: ./cleanup.sh"
else
    echo "❌ Demo failed to start. Check logs:"
    docker-compose logs
fi
