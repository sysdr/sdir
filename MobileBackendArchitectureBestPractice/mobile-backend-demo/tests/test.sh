#!/bin/bash

echo "🧪 Running Mobile Backend Tests"
echo "==============================="

# Test 1: Health checks
echo "Test 1: Health Checks"
curl -f http://localhost:3000/health || exit 1
curl -f http://localhost:3001/health || exit 1
curl -f http://localhost:3002/health || exit 1
echo "✅ All services healthy"

# Test 2: Optimistic write
echo -e "\nTest 2: Optimistic Write"
RESULT=$(curl -s -X POST http://localhost:3000/api/write \
  -H "Content-Type: application/json" \
  -d '{"deviceId":"test-device","key":"test-key","value":"test-value","vectorClock":{"test-device":1}}')
echo $RESULT | grep -q "acknowledged" || exit 1
echo "✅ Optimistic write acknowledged"

# Test 3: Sync endpoint
echo -e "\nTest 3: Sync Request"
RESULT=$(curl -s -X POST http://localhost:3000/api/sync \
  -H "Content-Type: application/json" \
  -H "X-Cursor: 0" \
  -d '{"deviceId":"test-device","networkQuality":"high"}')
echo $RESULT | grep -q "delta" || exit 1
echo "✅ Sync endpoint working"

# Test 4: Metrics
echo -e "\nTest 4: Metrics Collection"
RESULT=$(curl -s http://localhost:3000/api/metrics)
echo $RESULT | grep -q "syncRequests" || exit 1
echo "✅ Metrics available"

# Test 5: Queue status
echo -e "\nTest 5: Queue Status"
sleep 2
RESULT=$(curl -s http://localhost:3002/queue/status)
echo $RESULT | grep -q "queueSize" || exit 1
echo "✅ Queue monitoring working"

echo -e "\n✅ All tests passed!"
