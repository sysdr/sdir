#!/bin/bash

echo "🧪 Testing Dashboard Metrics..."
echo "==============================="

# Generate some load to ensure metrics are non-zero
echo ""
echo "1. Generating load across all regions..."
for i in {1..5}; do
    curl -s -X POST http://localhost:3000/api/write \
        -H "Content-Type: application/json" \
        -d "{\"region\":\"us-east\",\"key\":\"test-key-$i\",\"value\":\"test-value-$i\"}" > /dev/null
    sleep 0.2
done

for i in {1..5}; do
    curl -s -X POST http://localhost:3000/api/write \
        -H "Content-Type: application/json" \
        -d "{\"region\":\"us-west\",\"key\":\"test-key-$i\",\"value\":\"test-value-$i\"}" > /dev/null
    sleep 0.2
done

for i in {1..5}; do
    curl -s -X POST http://localhost:3000/api/write \
        -H "Content-Type: application/json" \
        -d "{\"region\":\"eu-west\",\"key\":\"test-key-$i\",\"value\":\"test-value-$i\"}" > /dev/null
    sleep 0.2
done

echo "✅ Load generated"
sleep 2

# Check stats from each region
echo ""
echo "2. Checking metrics from each region..."
for region in us-east us-west eu-west; do
    if [ "$region" = "us-east" ]; then port=3001; fi
    if [ "$region" = "us-west" ]; then port=3002; fi
    if [ "$region" = "eu-west" ]; then port=3003; fi
    
    stats=$(curl -s "http://localhost:$port/stats")
    writes=$(echo "$stats" | grep -o '"writes":[0-9]*' | cut -d: -f2)
    reads=$(echo "$stats" | grep -o '"reads":[0-9]*' | cut -d: -f2)
    replications=$(echo "$stats" | grep -o '"replications":[0-9]*' | cut -d: -f2)
    dataSize=$(echo "$stats" | grep -o '"dataSize":[0-9]*' | cut -d: -f2)
    
    echo ""
    echo "$region:"
    echo "  Writes: $writes"
    echo "  Reads: $reads"
    echo "  Replications: $replications"
    echo "  Data Size: $dataSize"
    
    if [ "$writes" = "0" ] && [ "$replications" = "0" ] && [ "$dataSize" = "0" ]; then
        echo "  ⚠️  WARNING: All metrics are zero!"
    else
        echo "  ✅ Metrics are non-zero"
    fi
done

# Test dashboard API
echo ""
echo "3. Testing Dashboard API endpoints..."
dashboard_test=$(curl -s http://localhost:3000/api/write -X POST \
    -H "Content-Type: application/json" \
    -d '{"region":"us-east","key":"dashboard-test","value":"dashboard-value"}')

if echo "$dashboard_test" | grep -q "success"; then
    echo "✅ Dashboard write API working"
else
    echo "❌ Dashboard write API failed: $dashboard_test"
fi

echo ""
echo "✅ Dashboard metrics test complete!"
echo ""
echo "🌍 Open http://localhost:3000 in your browser to view the dashboard"

