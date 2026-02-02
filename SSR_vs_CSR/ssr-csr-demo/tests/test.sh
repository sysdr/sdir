#!/bin/bash

echo "Running SSR vs CSR Demo Tests..."
echo ""

# Test 1: Metrics endpoint
echo "Test 1: Metrics endpoint..."
METRICS=$(curl -s http://localhost:3000/api/metrics 2>/dev/null)
if [ -z "$METRICS" ]; then
  echo "✗ Metrics endpoint not responding. Is the service running?"
  echo "  Run: cd ssr-csr-demo && ./start.sh"
  exit 1
fi
echo "✓ Metrics endpoint OK"

# Test 2: Dashboard
echo "Test 2: Dashboard accessibility..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/ 2>/dev/null)
if [ "$HTTP_CODE" != "200" ]; then
  echo "✗ Dashboard returned HTTP $HTTP_CODE"
  exit 1
fi
echo "✓ Dashboard OK"

# Test 3: SSR endpoint
echo "Test 3: SSR endpoint..."
SSR_HTML=$(curl -s http://localhost:3000/api/ssr 2>/dev/null)
if ! echo "$SSR_HTML" | grep -q "Server-Side Rendered"; then
  echo "✗ SSR endpoint failed"
  exit 1
fi
echo "✓ SSR endpoint OK"

# Test 4: CSR endpoint (returns HTML shell with Loading - client renders after)
echo "Test 4: CSR endpoint..."
CSR_HTML=$(curl -s http://localhost:3000/api/csr 2>/dev/null)
if ! echo "$CSR_HTML" | grep -qE "CSR Product Grid|Loading products"; then
  echo "✗ CSR endpoint failed"
  exit 1
fi
echo "✓ CSR endpoint OK"

# Test 5: Verify metrics are non-zero (run demo first if zero)
echo "Test 5: Dashboard metrics (non-zero after demo)..."
SSR_REQUESTS=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('ssr',{}).get('requests',0))" 2>/dev/null || echo "0")
CSR_REQUESTS=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('csr',{}).get('requests',0))" 2>/dev/null || echo "0")

if [ "$SSR_REQUESTS" = "0" ] && [ "$CSR_REQUESTS" = "0" ]; then
  echo "⚠️  Metrics are zero. Run './demo.sh' first to trigger traffic."
  echo "   Re-running demo traffic..."
  for i in 1 2 3 4 5; do
    curl -s -o /dev/null http://localhost:3000/api/ssr
    curl -s -o /dev/null http://localhost:3000/api/csr
  done
  sleep 1
  METRICS=$(curl -s http://localhost:3000/api/metrics 2>/dev/null)
  SSR_REQUESTS=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('ssr',{}).get('requests',0))" 2>/dev/null || echo "0")
  CSR_REQUESTS=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('csr',{}).get('requests',0))" 2>/dev/null || echo "0")
fi

if [ "$SSR_REQUESTS" != "0" ] || [ "$CSR_REQUESTS" != "0" ]; then
  echo "✓ Metrics populated: SSR=$SSR_REQUESTS requests, CSR=$CSR_REQUESTS requests"
else
  echo "✗ Metrics still zero after demo. Dashboard will show zeros."
  exit 1
fi

echo ""
echo "================================"
echo "All tests passed! ✓"
echo "================================"
