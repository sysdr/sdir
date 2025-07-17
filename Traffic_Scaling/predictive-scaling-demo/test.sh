#!/bin/bash

echo "🧪 Running Predictive Scaling Tests..."

# Test API endpoints
echo "Testing API endpoints..."

# Test historical data endpoint
echo "1. Testing historical data endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/historical-data)
if [ "$response" = "200" ]; then
    echo "✅ Historical data endpoint working"
else
    echo "❌ Historical data endpoint failed (HTTP $response)"
fi

# Test predictions endpoint
echo "2. Testing predictions endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/predictions)
if [ "$response" = "200" ]; then
    echo "✅ Predictions endpoint working"
else
    echo "❌ Predictions endpoint failed (HTTP $response)"
fi

# Test scaling decisions endpoint
echo "3. Testing scaling decisions endpoint..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/scaling-decisions)
if [ "$response" = "200" ]; then
    echo "✅ Scaling decisions endpoint working"
else
    echo "❌ Scaling decisions endpoint failed (HTTP $response)"
fi

# Test traffic spike simulation
echo "4. Testing traffic spike simulation..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:5000/api/simulate-traffic-spike)
if [ "$response" = "200" ]; then
    echo "✅ Traffic spike simulation working"
else
    echo "❌ Traffic spike simulation failed (HTTP $response)"
fi

echo ""
echo "🎯 All tests completed!"
