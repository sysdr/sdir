#!/bin/bash

# Test script for Long-tail Latency Observatory

set -e

echo "🧪 Testing Long-tail Latency Observatory..."

# Wait for service to be ready
echo "Waiting for service to be ready..."
timeout=60
counter=0

while [ $counter -lt $timeout ]; do
    if curl -s http://localhost:8000/api/health > /dev/null; then
        echo "✅ Service is ready!"
        break
    fi
    sleep 1
    counter=$((counter + 1))
done

if [ $counter -eq $timeout ]; then
    echo "❌ Service failed to start within $timeout seconds"
    exit 1
fi

# Run tests
echo "Running API tests..."

# Test health endpoint
echo "Testing health endpoint..."
curl -s http://localhost:8000/api/health | grep -q "healthy" || (echo "❌ Health check failed" && exit 1)

# Test configuration
echo "Testing configuration endpoint..."
curl -s http://localhost:8000/api/config > /dev/null || (echo "❌ Config endpoint failed" && exit 1)

# Test simulation
echo "Testing request simulation..."
curl -s http://localhost:8000/api/simulate | grep -q "response_time_ms" || (echo "❌ Simulation failed" && exit 1)

# Test metrics
echo "Testing metrics endpoint..."
curl -s http://localhost:8000/api/metrics | grep -q "recent_stats" || (echo "❌ Metrics failed" && exit 1)

echo "✅ All tests passed!"
echo "🌐 Dashboard available at: http://localhost:8000"
