#!/bin/bash

set -e

echo "🚀 Blue-Green Deployment Demo Setup"
echo "===================================="

# Check prerequisites
echo "📋 Checking prerequisites..."
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed."
    exit 1
fi

if ! docker compose version &> /dev/null; then
    echo "❌ Docker Compose is required but not installed."
    exit 1
fi

echo "✅ Prerequisites satisfied"

# Build and start services
echo ""
echo "🔨 Building Docker images..."
docker compose build --no-cache

echo ""
echo "🚀 Starting services..."
docker compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 20

# Check service health
echo ""
echo "🏥 Checking service health..."
for i in {1..12}; do
    if curl -s http://localhost:8001/health > /dev/null && \
       curl -s http://localhost:8002/health > /dev/null && \
       curl -s http://localhost:3000 > /dev/null; then
        echo "✅ All services are healthy!"
        break
    fi
    
    if [ $i -eq 12 ]; then
        echo "❌ Services failed to start properly"
        echo "🔍 Checking logs..."
        docker compose logs
        exit 1
    fi
    
    echo "⏳ Waiting for services... (attempt $i/12)"
    sleep 10
done

echo ""
echo "🧪 Running tests..."
python3 tests/test_deployment.py

echo ""
echo "🎉 Blue-Green Deployment Demo is ready!"
echo ""
echo "📊 Access Points:"
echo "   🌐 Dashboard:      http://localhost:3000"
echo "   🔵 Blue App:       http://localhost:8001"
echo "   🟢 Green App:      http://localhost:8002"
echo "   🔄 Load Balancer:  http://localhost:8000"
echo ""
echo "🎯 Demo Instructions:"
echo "1. Open the dashboard at http://localhost:3000"
echo "2. Observe both Blue and Green environments"
echo "3. Try deploying to Green environment"
echo "4. Switch traffic between environments"
echo "5. Test emergency rollback functionality"
echo ""
echo "🛠️ Commands:"
echo "   View logs:    docker compose logs -f"
echo "   Stop demo:    ./cleanup.sh"
echo "   Restart:      docker compose restart"

# Open browser (optional)
if command -v open &> /dev/null; then
    echo ""
    echo "🌐 Opening dashboard in browser..."
    sleep 2
    open http://localhost:3000
elif command -v xdg-open &> /dev/null; then
    echo ""
    echo "🌐 Opening dashboard in browser..."
    sleep 2
    xdg-open http://localhost:3000
fi

echo ""
echo "✅ Demo setup complete! Enjoy exploring Blue-Green deployments!"
