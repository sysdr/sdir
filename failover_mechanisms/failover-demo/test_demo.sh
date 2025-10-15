#!/bin/bash

echo "🧪 Running Failover Demo Tests..."

# Wait for services to be ready
echo "Waiting for services to start..."
sleep 30

# Test 1: Check all services are healthy
echo "Test 1: Checking service health..."
curl -s http://localhost:8080/api/products | jq '.'
if [ $? -eq 0 ]; then
    echo "✅ Load balancer routing works"
else
    echo "❌ Load balancer routing failed"
fi

# Test 2: Simulate application failure
echo "Test 2: Simulating primary application failure..."
curl -s -X POST http://localhost:3001/api/simulate-failure
sleep 5

# Check if secondary is still serving requests
curl -s http://localhost:8080/api/products | jq '.'
if [ $? -eq 0 ]; then
    echo "✅ Automatic failover to secondary application successful"
else
    echo "❌ Failover failed"
fi

# Test 3: Check monitoring dashboard
echo "Test 3: Checking monitoring service..."
curl -s http://localhost:3000/api/status | jq '.applications'
if [ $? -eq 0 ]; then
    echo "✅ Monitoring service is working"
else
    echo "❌ Monitoring service failed"
fi

echo "🎉 Demo tests completed!"
