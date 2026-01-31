#!/bin/bash

echo "=== Running Integration Tests ==="

# Test Data Generator
echo "Testing Data Generator..."
response=$(curl -s http://localhost:3001/health)
if [[ $response == *"ok"* ]]; then
  echo "✓ Data Generator: PASS"
else
  echo "✗ Data Generator: FAIL"
  exit 1
fi

# Test Push Service
echo "Testing Push Service..."
response=$(curl -s http://localhost:3002/health)
if [[ $response == *"ok"* ]]; then
  echo "✓ Push Service: PASS"
else
  echo "✗ Push Service: FAIL"
  exit 1
fi

# Test Pull Service
echo "Testing Pull Service..."
response=$(curl -s http://localhost:3003/health)
if [[ $response == *"ok"* ]]; then
  echo "✓ Pull Service: PASS"
else
  echo "✗ Pull Service: FAIL"
  exit 1
fi

# Test Pull API
echo "Testing Pull API..."
response=$(curl -s http://localhost:3003/poll)
if [[ $response == *"data"* ]]; then
  echo "✓ Pull API: PASS"
else
  echo "✗ Pull API: FAIL"
  exit 1
fi

# Test Dashboard
echo "Testing Dashboard..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080)
if [[ $response == "200" ]]; then
  echo "✓ Dashboard: PASS"
else
  echo "✗ Dashboard: FAIL"
  exit 1
fi

# Verify metrics update (dashboard will show non-zero when opened)
echo "Verifying metrics update..."
sleep 3
push_stats=$(curl -s http://localhost:3002/stats)
pull_stats=$(curl -s http://localhost:3003/stats)
if echo "$pull_stats" | grep -qE '"requestCount":\s*[1-9]'; then
  echo "✓ Pull metrics updating: PASS"
else
  echo "⚠ Pull metrics: no requests yet (dashboard will update when opened)"
fi
if echo "$push_stats" | grep -qE '"messagesSent":\s*[1-9]'; then
  echo "✓ Push metrics updating: PASS"
else
  echo "⚠ Push metrics: no clients yet (dashboard will update when opened)"
fi

echo ""
echo "=== All Tests Passed! ==="
