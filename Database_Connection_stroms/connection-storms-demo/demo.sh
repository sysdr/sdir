#!/bin/bash
# Quick demo: trigger a connection storm and observe behavior
BASE="http://localhost:3001"
echo "🌩  Triggering storm on DIRECT connections (25 concurrent, 600ms hold)..."
curl -s -X POST "$BASE/api/storm/direct" -H "Content-Type: application/json" -d '{"concurrency":25,"holdMs":600}' | python3 -m json.tool 2>/dev/null || echo "(started)"
sleep 6
echo ""
echo "📊 Direct storm metrics:"
curl -s "$BASE/api/metrics" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  Total: {d[\"direct\"][\"totalRequests\"]}, Rejected: {d[\"direct\"][\"rejectedRequests\"]}, Avg latency: {d[\"direct\"][\"avgLatencyMs\"]}ms')" 2>/dev/null

echo ""
curl -s -X POST "$BASE/api/reset" > /dev/null
echo "🛡  Triggering storm on POOLED connections (same settings)..."
curl -s -X POST "$BASE/api/storm/pooled" -H "Content-Type: application/json" -d '{"concurrency":25,"holdMs":600}' | python3 -m json.tool 2>/dev/null || echo "(started)"
sleep 6
echo ""
echo "📊 Pooled storm metrics:"
curl -s "$BASE/api/metrics" | python3 -c "import json,sys; d=json.load(sys.stdin); print(f'  Total: {d[\"pooled\"][\"totalRequests\"]}, Rejected: {d[\"pooled\"][\"rejectedRequests\"]}, Avg latency: {d[\"pooled\"][\"avgLatencyMs\"]}ms')" 2>/dev/null
echo ""
echo "✅ Open http://localhost:3000 to view the live dashboard"
