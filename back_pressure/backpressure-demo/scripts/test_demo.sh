#!/bin/bash

# Test script for backpressure demo
echo "🧪 Testing Backpressure Demo..."

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 30

# Test 1: Health checks
echo "✅ Testing service health..."
curl -f http://localhost:8000/health || echo "❌ Gateway health check failed"
curl -f http://localhost:8001/health || echo "❌ Backend health check failed"
curl -f http://localhost:3000/ || echo "❌ Dashboard health check failed"

# Reset circuit breaker and backend latency for clean test
echo "🔄 Resetting system state for testing..."
curl -s -X POST http://localhost:8001/config/latency/0.1 > /dev/null
echo "⏳ Waiting for circuit breaker to reset (30 seconds)..."
sleep 30

# Robustly wait for circuit breaker to close
max_retries=20
success=0
echo "🔄 Probing /api/process to close circuit breaker..."
for i in $(seq 1 $max_retries); do
    response=$(curl -s http://localhost:8000/api/process)
    if echo "$response" | grep -q '"status":"success"'; then
        echo "✅ Circuit breaker closed after $i attempts."
        success=1
        break
    else
        echo "Attempt $i: Circuit breaker still open or backend unhealthy. Response: $response"
        sleep 1
    fi
done
if [ $success -ne 1 ]; then
    echo "❌ Circuit breaker did not close after $max_retries attempts. Aborting test."
    exit 1
fi

# Test 2: Normal operation
echo "✅ Testing normal operation..."
response=$(curl -s http://localhost:8000/api/process)
if echo "$response" | grep -q '"status":"success"'; then
    echo "✅ Normal operation test passed"
else
    echo "❌ Normal operation test failed"
    echo "Response: $response"
fi

# Test 3: Backpressure activation
echo "✅ Testing backpressure activation..."
curl -s -X POST http://localhost:8001/config/latency/2.0
sleep 5

# Generate some load
for i in {1..10}; do
    curl -s http://localhost:8000/api/process &
done
wait

echo "✅ Backpressure demo tests completed"
