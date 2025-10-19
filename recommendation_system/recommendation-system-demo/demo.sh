#!/bin/bash

set -e

echo "🚀 Starting Recommendation System Demo..."

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required"; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required"; exit 1; }

# Build and start services
echo "📦 Building containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Run tests
echo "🧪 Running tests..."
docker-compose exec backend python -m pytest /app/tests/ -v || {
    echo "Running tests with requests..."
    python3 tests/test_recommendations.py
}

echo "
🎉 Demo is ready!

🌐 Access points:
   Frontend: http://localhost:3000
   API: http://localhost:8000
   API Docs: http://localhost:8000/docs

🎯 Demo features:
   - Real-time hybrid recommendations
   - Multiple algorithm comparison
   - Interactive user testing
   - Performance monitoring
   - A/B testing results

📊 Try these actions:
   1. Select different users to see personalized recommendations
   2. Rate items to see recommendation changes
   3. Compare different algorithms (collaborative, content-based, hybrid)
   4. Monitor real-time performance metrics

🛑 Stop demo: ./cleanup.sh
"
