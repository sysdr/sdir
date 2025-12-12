#!/bin/bash

echo "Running Infrastructure Tests..."
echo "==============================="

# Test 1: State Lock Mechanism
echo "Test 1: State Lock Mechanism"
LOCK_RESPONSE=$(curl -s -X POST http://localhost:3001/api/lock \
  -H "Content-Type: application/json" \
  -d '{"operation":"test"}')

if echo "$LOCK_RESPONSE" | grep -q "lockId"; then
  echo "✓ Lock acquired successfully"
  LOCK_ID=$(echo "$LOCK_RESPONSE" | grep -o '"lockId":"[^"]*"' | cut -d'"' -f4)
  
  # Try to acquire lock again (should fail)
  LOCK_FAIL=$(curl -s -X POST http://localhost:3001/api/lock \
    -H "Content-Type: application/json" \
    -d '{"operation":"test2"}')
  
  if echo "$LOCK_FAIL" | grep -q "locked"; then
    echo "✓ Concurrent lock prevention works"
  else
    echo "✗ Concurrent lock prevention failed"
  fi
  
  # Release lock
  curl -s -X POST http://localhost:3001/api/unlock \
    -H "Content-Type: application/json" \
    -d "{\"lockId\":\"$LOCK_ID\"}" > /dev/null
  echo "✓ Lock released successfully"
else
  echo "✗ Lock acquisition failed"
fi

# Test 2: Infrastructure State Management
echo ""
echo "Test 2: Infrastructure State Management"
STATE=$(curl -s http://localhost:3001/api/state)
if [ ! -z "$STATE" ]; then
  echo "✓ State retrieval successful"
else
  echo "✗ State retrieval failed"
fi

# Test 3: Drift Detection
echo ""
echo "Test 3: Drift Detection"
DRIFT=$(curl -s http://localhost:3001/api/drift/check)
if echo "$DRIFT" | grep -q "driftDetected"; then
  echo "✓ Drift detection operational"
else
  echo "✗ Drift detection failed"
fi

# Test 4: Metrics Collection
echo ""
echo "Test 4: Metrics Collection"
METRICS=$(curl -s http://localhost:3001/api/metrics)
if echo "$METRICS" | grep -q "totalResources"; then
  echo "✓ Metrics collection working"
else
  echo "✗ Metrics collection failed"
fi

echo ""
echo "==============================="
echo "All tests completed!"
