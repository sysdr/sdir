#!/bin/bash

echo "🧪 Testing Fraud Detection System..."

# Wait for services
sleep 10

# Test 1: Submit normal transaction
echo "Test 1: Normal transaction..."
RESPONSE=$(curl -s -X POST http://localhost:3001/api/transactions \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "user-123",
    "amount": 50.00,
    "merchant": "Amazon",
    "deviceId": "device-456",
    "ipAddress": "192.168.1.1",
    "latitude": 40.7128,
    "longitude": -74.0060
  }')

if echo "$RESPONSE" | grep -q "success"; then
  echo "✅ Test 1 passed"
else
  echo "❌ Test 1 failed"
  exit 1
fi

sleep 2

# Test 2: High velocity fraud
echo "Test 2: High velocity fraud pattern..."
for i in {1..5}; do
  curl -s -X POST http://localhost:3001/api/transactions \
    -H "Content-Type: application/json" \
    -d '{
      "userId": "user-fraud",
      "amount": 999.00,
      "merchant": "Suspicious Shop",
      "deviceId": "device-suspicious",
      "ipAddress": "192.168.1.100",
      "latitude": 40.7128,
      "longitude": -74.0060
    }' > /dev/null
  sleep 0.5
done

sleep 5

# Test 3: Check stats
echo "Test 3: Checking system stats..."
STATS=$(curl -s http://localhost:3001/api/stats)

if echo "$STATS" | grep -q "total"; then
  echo "✅ Test 3 passed"
else
  echo "❌ Test 3 failed"
  exit 1
fi

echo "✅ All tests passed!"
