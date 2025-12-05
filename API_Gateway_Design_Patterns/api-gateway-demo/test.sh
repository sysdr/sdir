#!/bin/bash

echo "Running API Gateway Tests..."
echo "======================================"

# Wait for services
sleep 10

# Test 1: Health Check
echo ""
echo "Test 1: Gateway Health Check"
curl -s http://localhost:3000/health | jq '.'

# Test 2: Authentication
echo ""
echo "Test 2: JWT Authentication"
TOKEN=$(curl -s -X POST http://localhost:3000/api/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test-user"}' | jq -r '.token')
echo "Token obtained: ${TOKEN:0:20}..."

# Test 3: Web BFF Pattern
echo ""
echo "Test 3: Web BFF Pattern (Full Data)"
curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.metadata'

# Test 4: Mobile BFF Pattern
echo ""
echo "Test 4: Mobile BFF Pattern (Optimized)"
curl -s http://localhost:3000/api/mobile/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.performance'

# Test 5: Cache Performance
echo ""
echo "Test 5: Cache Performance (Second request should be cached)"
time curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" > /dev/null
echo "Second request (should hit cache):"
time curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.metadata | {cached, totalLatency}'

# Test 6: Rate Limiting
echo ""
echo "Test 6: Rate Limiting (Rapid fire requests)"
for i in {1..5}; do
  STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    http://localhost:3000/api/web/dashboard \
    -H "Authorization: Bearer $TOKEN")
  echo "Request $i: HTTP $STATUS"
  sleep 0.1
done

# Test 7: Orchestration Timing
echo ""
echo "Test 7: Request Orchestration (Parallel vs Sequential)"
echo "Parallel execution through gateway shows combined latency..."
curl -s http://localhost:3000/api/web/dashboard \
  -H "Authorization: Bearer $TOKEN" | jq '.metadata.servicesStatus'

echo ""
echo "======================================"
echo "All tests completed!"
echo "Open http://localhost:8080 to see the dashboard"
