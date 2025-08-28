#!/bin/bash

echo "🚀 Starting Canary Deployment Demo..."

# Build and start services
echo "📦 Building Docker images..."
docker-compose build

echo "🎬 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 15

# Check service health
echo "🏥 Checking service health..."
docker-compose ps

echo "✅ Demo is ready!"
echo ""
echo "🌐 Access points:"
echo "   Dashboard: http://localhost:4000"
echo "   Application: http://localhost:8080"
echo "   Stable app direct: http://localhost:8080 (routed)"
echo ""
echo "🎯 Demo steps:"
echo "1. Open dashboard: http://localhost:4000"
echo "2. Click 'Test Traffic' to see 100% stable traffic"
echo "3. Click '10% Canary' to start canary deployment"
echo "4. Click 'Test Traffic' again to see traffic split"
echo "5. Try 'Simulate Issues' to see rollback scenario"
echo "6. Progress through 25% → 50% → 100% for full rollout"
echo ""
echo "📊 Monitor logs with: docker-compose logs -f"
echo "🛑 Stop demo with: ./cleanup.sh"
