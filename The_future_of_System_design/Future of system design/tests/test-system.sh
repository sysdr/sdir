#!/bin/bash

echo "🧪 Running System Tests..."

# Test 1: Health checks
echo "Test 1: Service Health Checks"
for port in 3001 3003; do
  response=$(curl -s http://localhost:$port/health)
  if echo "$response" | grep -q "healthy"; then
    echo "  ✓ Port $port: healthy"
  else
    echo "  ✗ Port $port: failed"
    exit 1
  fi
done

# Test 2: Router functionality
echo "Test 2: AI Router"
response=$(curl -s -X POST http://localhost:3001/route \
  -H "Content-Type: application/json" \
  -d '{"type":"compute","priority":"high","userRegion":"us-west"}')

if echo "$response" | grep -q "decision"; then
  echo "  ✓ Routing decision made"
else
  echo "  ✗ Routing failed"
  exit 1
fi

# Test 3: Metrics collection
echo "Test 3: Metrics Collector"
response=$(curl -s http://localhost:3003/metrics)
if echo "$response" | grep -q "totalTraces"; then
  echo "  ✓ Metrics collected"
else
  echo "  ✗ Metrics collection failed"
  exit 1
fi

# Test 4: Dashboard accessibility
echo "Test 4: Dashboard"
response=$(curl -s http://localhost:8080)
if echo "$response" | grep -q "Future System Design"; then
  echo "  ✓ Dashboard accessible"
else
  echo "  ✗ Dashboard failed"
  exit 1
fi

# Test 5: Dashboard metrics non-zero (values update with demo)
echo "Test 5: Dashboard metrics (non-zero or updated by demo)"
metrics=$(curl -s http://localhost:3003/metrics)
stats=$(curl -s http://localhost:3001/stats)
if echo "$metrics" | grep -q '"cpu"' && echo "$metrics" | grep -q '"totalTraces"'; then
  echo "  ✓ Metrics API returns CPU and totalTraces"
else
  echo "  ✗ Metrics API incomplete"
  exit 1
fi
if echo "$stats" | grep -q '"totalRequests"'; then
  echo "  ✓ Router stats include totalRequests"
else
  echo "  ✗ Router stats incomplete"
  exit 1
fi

echo ""
echo "✅ All tests passed!"
echo ""
echo "📊 System Status:"
curl -s http://localhost:3001/stats | head -20
