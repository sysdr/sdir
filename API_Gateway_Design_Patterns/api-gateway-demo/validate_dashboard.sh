#!/bin/bash

echo "Validating Dashboard Metrics..."
echo "======================================"

API_URL="http://localhost:3000"
FAILED=0

# Get JWT token
echo ""
echo "1. Authenticating..."
RESPONSE=$(curl -s -X POST "$API_URL/api/login" \
  -H "Content-Type: application/json" \
  -d '{"username":"demo-user"}')
TOKEN=$(echo "$RESPONSE" | grep -o '"token":"[^"]*' | cut -d'"' -f4)

if [ -z "$TOKEN" ] || [ "$TOKEN" == "null" ]; then
    echo "❌ Authentication failed"
    echo "Response: $RESPONSE"
    exit 1
fi
echo "✓ Authentication successful"

# Test Web BFF - should generate metrics
echo ""
echo "2. Testing Web BFF (should update metrics)..."
for i in {1..3}; do
    RESPONSE=$(curl -s "$API_URL/api/web/dashboard" \
      -H "Authorization: Bearer $TOKEN")
    
    if echo "$RESPONSE" | grep -q "totalLatency"; then
        LATENCY=$(echo "$RESPONSE" | grep -o '"totalLatency":[0-9]*' | cut -d':' -f2)
        echo "  Request $i: Latency = ${LATENCY}ms"
        
        if [ ! -z "$LATENCY" ] && [ "$LATENCY" != "0" ]; then
            echo "  ✓ Metrics updating (latency: ${LATENCY}ms)"
        else
            echo "  ⚠ Warning: Latency is zero or null"
            FAILED=$((FAILED + 1))
        fi
    else
        echo "  ❌ Invalid response"
        FAILED=$((FAILED + 1))
    fi
    sleep 1
done

# Test Mobile BFF
echo ""
echo "3. Testing Mobile BFF..."
RESPONSE=$(curl -s "$API_URL/api/mobile/dashboard" \
  -H "Authorization: Bearer $TOKEN")
LATENCY=$(echo "$RESPONSE" | grep -o '"totalLatency":[0-9]*' | cut -d':' -f2 || echo "0")
if [ ! -z "$LATENCY" ] && [ "$LATENCY" != "0" ]; then
    echo "✓ Mobile BFF working (latency: ${LATENCY}ms)"
else
    echo "⚠ Warning: Mobile BFF latency is zero"
    FAILED=$((FAILED + 1))
fi

# Check Prometheus metrics
echo ""
echo "4. Checking Prometheus metrics endpoint..."
METRICS=$(curl -s "$API_URL/metrics")
if echo "$METRICS" | grep -q "http_request_duration_ms"; then
    echo "✓ Prometheus metrics endpoint working"
    
    # Check for non-zero values
    REQUEST_COUNT=$(echo "$METRICS" | grep "http_request_duration_ms_count" | head -1 | awk '{print $2}' || echo "0")
    if [ "$REQUEST_COUNT" != "0" ] && [ ! -z "$REQUEST_COUNT" ]; then
        echo "  ✓ Request count: $REQUEST_COUNT (non-zero)"
    else
        echo "  ⚠ Warning: Request count is zero"
        FAILED=$((FAILED + 1))
    fi
else
    echo "❌ Prometheus metrics not found"
    FAILED=$((FAILED + 1))
fi

# Check cache metrics
echo ""
echo "5. Checking cache metrics..."
CACHE_HITS=$(echo "$METRICS" | grep "^cache_hits_total" | grep -v "#" | awk '{print $2}' | head -1 || echo "0")
CACHE_MISSES=$(echo "$METRICS" | grep "^cache_misses_total" | grep -v "#" | awk '{print $2}' | head -1 || echo "0")
if [ "$CACHE_HITS" == "HELP" ] || [ -z "$CACHE_HITS" ]; then CACHE_HITS="0"; fi
if [ "$CACHE_MISSES" == "HELP" ] || [ -z "$CACHE_MISSES" ]; then CACHE_MISSES="0"; fi
echo "  Cache hits: $CACHE_HITS"
echo "  Cache misses: $CACHE_MISSES"

# Make a second request to test caching
echo ""
echo "6. Testing cache (second request should hit cache)..."
curl -s "$API_URL/api/web/dashboard" -H "Authorization: Bearer $TOKEN" > /dev/null
sleep 2
METRICS_AFTER=$(curl -s "$API_URL/metrics")
CACHE_HITS_AFTER=$(echo "$METRICS_AFTER" | grep "^cache_hits_total" | grep -v "#" | awk '{print $2}' | head -1 || echo "0")
if [ "$CACHE_HITS_AFTER" == "HELP" ] || [ -z "$CACHE_HITS_AFTER" ]; then CACHE_HITS_AFTER="0"; fi
if [ "$CACHE_HITS_AFTER" -gt "$CACHE_HITS" ] 2>/dev/null; then
    echo "✓ Cache is working (hits increased from $CACHE_HITS to $CACHE_HITS_AFTER)"
else
    echo "⚠ Cache may not be working (hits: $CACHE_HITS -> $CACHE_HITS_AFTER)"
fi

# Check dashboard accessibility
echo ""
echo "7. Checking dashboard accessibility..."
if curl -s -o /dev/null -w "%{http_code}" "http://localhost:8080" | grep -q "200"; then
    echo "✓ Dashboard is accessible at http://localhost:8080"
else
    echo "❌ Dashboard not accessible"
    FAILED=$((FAILED + 1))
fi

# Summary
echo ""
echo "======================================"
if [ $FAILED -eq 0 ]; then
    echo "✅ All dashboard validations passed!"
    echo ""
    echo "Dashboard URL: http://localhost:8080"
    echo "Metrics URL: http://localhost:3000/metrics"
    exit 0
else
    echo "⚠ $FAILED validation(s) failed or had warnings"
    echo ""
    echo "Please check the dashboard at http://localhost:8080"
    echo "and verify metrics are updating when you click test buttons."
    exit 1
fi

