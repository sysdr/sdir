#!/bin/bash
set -e

echo "🧪 Running RTB System Tests..."

# Wait for services
sleep 5

# Test Exchange health
echo "Testing Exchange..."
curl -f http://localhost:3001/health || exit 1

# Test Bidders
echo "Testing Bidders..."
curl -f http://localhost:3003/health || exit 1
curl -f http://localhost:3004/health || exit 1
curl -f http://localhost:3005/health || exit 1

# Get stats after a few auctions
sleep 3
STATS=$(curl -s http://localhost:3001/stats)
echo "Exchange Stats: $STATS"

P99=$(echo $STATS | grep -o '"p99":[0-9]*' | cut -d: -f2)
if [ -z "$P99" ]; then
  echo "❌ No auction data"
  exit 1
fi

echo "✅ All tests passed!"
echo "📊 P99 Latency: ${P99}ms"
