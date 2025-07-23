#!/bin/bash

# ML Inference Scaling Demo Runner
set -e

echo "🚀 Starting ML Inference Scaling Demo..."

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is required but not installed"
    exit 1
fi

# Build and start services
echo "🏗️  Building Docker images..."
docker-compose build --no-cache

echo "🚀 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 10

# Wait for health checks
echo "🔍 Checking service health..."
for i in {1..30}; do
    if curl -s http://localhost:8000/health > /dev/null 2>&1; then
        echo "✅ ML Inference service is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "❌ Service failed to start within timeout"
        docker-compose logs ml-inference
        exit 1
    fi
    sleep 2
done

# Run basic functionality test
echo "🧪 Running basic functionality tests..."
python3 -c "
import requests
import json

# Test health endpoint
response = requests.get('http://localhost:8000/health')
assert response.status_code == 200, f'Health check failed: {response.status_code}'

# Test prediction endpoint
test_data = {'text': 'This is a great demo!', 'id': 'demo_test'}
response = requests.post('http://localhost:8000/predict', json=test_data)
assert response.status_code == 200, f'Prediction failed: {response.status_code}'

result = response.json()
assert 'sentiment' in result, 'Missing sentiment in response'
assert 'confidence' in result, 'Missing confidence in response'

print('✅ Basic functionality tests passed!')
"

# Run performance tests
echo "⚡ Running performance tests..."
if command -v python3 &> /dev/null; then
    cd tests
    python3 load_test.py --requests 20 --concurrency 5 --text "Performance testing the ML inference system"
    cd ..
else
    echo "⚠️  Python3 not available, skipping performance tests"
fi

# Display access information
echo ""
echo "🎉 Demo is ready!"
echo ""
echo "📊 Access Points:"
echo "   Web Interface:  http://localhost:8000"
echo "   Health Check:   http://localhost:8000/health"
echo "   Metrics:        http://localhost:8000/metrics"
echo "   API Docs:       http://localhost:8000/docs"
echo ""
echo "🔧 Useful Commands:"
echo "   View logs:      docker-compose logs -f ml-inference"
echo "   Stop demo:      ./cleanup.sh"
echo "   Run tests:      docker-compose run --rm load-tester"
echo ""
echo "📈 Try these demo scenarios:"
echo "   1. Single predictions with different text inputs"
echo "   2. Batch testing with various batch sizes"
echo "   3. Load testing to observe dynamic batching"
echo "   4. Monitor metrics and performance characteristics"
echo ""

# Keep services running and show logs
echo "📋 Showing live logs (Ctrl+C to stop):"
docker-compose logs -f ml-inference
