#!/bin/bash

echo "🔥 Hot Partition Detection Demo"
echo "================================"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start services
echo "🏗️ Building and starting services..."
docker-compose up --build -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Check service health
echo "🔍 Checking service health..."
max_attempts=30
attempt=0

while [ $attempt -lt $max_attempts ]; do
    if curl -s http://localhost:8000/api/metrics > /dev/null; then
        echo "✅ API service is ready!"
        break
    fi
    
    echo "Waiting for API service... (attempt $((attempt + 1))/$max_attempts)"
    sleep 2
    attempt=$((attempt + 1))
done

if [ $attempt -eq $max_attempts ]; then
    echo "❌ API service failed to start"
    docker-compose logs
    exit 1
fi

# Run tests
echo "🧪 Running tests..."
docker-compose exec -T hot-partition-api python -m pytest tests/ -v

# Show service status
echo "📊 Service Status:"
docker-compose ps

echo ""
echo "🎉 Demo is ready!"
echo ""
echo "🌐 Access the dashboard: http://localhost:8000"
echo "📊 API endpoints: http://localhost:8000/docs"
echo ""
echo "📝 Demo Instructions:"
echo "1. Open http://localhost:8000 in your browser"
echo "2. Watch the normal partition distribution"
echo "3. Click 'Trigger Hotspot' to simulate a hot partition"
echo "4. Observe the entropy drop and alerts generated"
echo "5. Watch the mitigation recommendations"
echo "6. Click 'End Hotspot' to return to normal"
echo ""
echo "🔥 Key Features to Observe:"
echo "• Entropy score changes (watch for values < 0.7)"
echo "• Request distribution becoming skewed"
echo "• Memory usage correlation"
echo "• Real-time alert generation"
echo "• Partition status color changes"
echo ""
echo "📊 To view logs: docker-compose logs -f"
echo "🛑 To stop demo: ./cleanup.sh"
