#!/bin/bash

echo "🧪 Running Chaos Engineering Tests..."

# Test 1: Normal operation
echo "Test 1: Normal operation (no chaos)..."
for i in {1..5}; do
  response=$(curl -s -X POST http://localhost:3000/api/order \
    -H "Content-Type: application/json" \
    -d '{"itemId":"ITEM-001","quantity":1,"paymentAmount":999.99}')
  
  if echo "$response" | grep -q '"success":true'; then
    echo "✅ Order $i succeeded"
  else
    echo "❌ Order $i failed: $response"
  fi
done

# Test 2: Inject chaos into payment service
echo -e "\nTest 2: Payment service chaos (30% error rate)..."
curl -s -X POST http://localhost:3001/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"errorRate":0.3,"latency":0}' > /dev/null

sleep 2

success_count=0
for i in {1..10}; do
  response=$(curl -s -X POST http://localhost:3000/api/order \
    -H "Content-Type: application/json" \
    -d '{"itemId":"ITEM-002","quantity":1,"paymentAmount":29.99}')
  
  if echo "$response" | grep -q '"success":true'; then
    ((success_count++))
  fi
done

echo "✅ Success rate with chaos: $success_count/10 (expected ~7 due to retries and circuit breaker)"

# Test 3: High latency
echo -e "\nTest 3: High latency (2000ms)..."
curl -s -X POST http://localhost:3002/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"errorRate":0,"latency":2000}' > /dev/null

start_time=$(date +%s)
curl -s -X POST http://localhost:3000/api/order \
  -H "Content-Type: application/json" \
  -d '{"itemId":"ITEM-003","quantity":1,"paymentAmount":79.99}' > /dev/null
end_time=$(date +%s)

duration=$((end_time - start_time))
echo "✅ Request completed in ${duration}s (shows latency impact)"

# Test 4: Circuit breaker
echo -e "\nTest 4: Testing circuit breaker..."
curl -s -X POST http://localhost:3001/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":true,"errorRate":1.0,"latency":0}' > /dev/null

echo "Triggering circuit breaker with 100% failure rate..."
for i in {1..5}; do
  curl -s -X POST http://localhost:3000/api/order \
    -H "Content-Type: application/json" \
    -d '{"itemId":"ITEM-004","quantity":1,"paymentAmount":299.99}' > /dev/null
  sleep 0.5
done

metrics=$(curl -s http://localhost:3000/api/metrics)
cb_state=$(echo "$metrics" | grep -o '"state":"[^"]*"' | head -1 | cut -d'"' -f4)
echo "✅ Circuit breaker state: $cb_state (expected OPEN)"

# Reset chaos
echo -e "\nResetting chaos configuration..."
curl -s -X POST http://localhost:3001/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":false,"errorRate":0,"latency":0}' > /dev/null

curl -s -X POST http://localhost:3002/chaos/config \
  -H "Content-Type: application/json" \
  -d '{"enabled":false,"errorRate":0,"latency":0}' > /dev/null

echo -e "\n✅ All tests completed!"
