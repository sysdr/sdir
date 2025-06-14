#!/bin/bash

echo "🔬 Testing Service Discovery Patterns"
echo "===================================="

# Test basic service calls
echo "1. Testing User Service through Gateway..."
curl -s http://localhost:8000/api/users | jq '.'

echo -e "\n2. Testing Order Service (with user discovery)..."
curl -s http://localhost:8000/api/orders/1 | jq '.'

echo -e "\n3. Testing Discovery API..."
curl -s http://localhost:8000/api/discovery/services | jq '.'

# Test failure scenarios
echo -e "\n4. Testing Circuit Breaker (stopping user-service-2)..."
docker-compose stop user-service-2
sleep 5

echo "Calling order service after user-service-2 failure..."
curl -s http://localhost:8000/api/orders/1 | jq '.'

echo -e "\n5. Restarting user-service-2..."
docker-compose start user-service-2
sleep 10

echo "Service should recover automatically..."
curl -s http://localhost:8000/api/orders/1 | jq '.'

echo -e "\n✅ Discovery testing complete!"
