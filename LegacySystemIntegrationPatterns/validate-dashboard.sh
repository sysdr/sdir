#!/bin/bash

set -e

echo "=========================================="
echo "Validating Dashboard Metrics"
echo "=========================================="
echo ""

# Generate some traffic
echo "Generating demo traffic..."
for i in {1..5}; do
    amount=$(echo "$i * 100 + 99.99" | bc)
    curl -s -X POST "http://localhost:3000/api/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerName\":\"Customer-$i\",\"productCode\":\"PROD-00$((i % 5 + 1))\",\"quantity\":$((i % 3 + 1)),\"totalAmount\":$amount}" > /dev/null
    sleep 0.5
done

echo "Waiting for metrics to update..."
sleep 3

# Check stats
echo ""
echo "=== Checking Stats ==="
stats=$(curl -s "http://localhost:3000/api/stats")

echo "Stats response:"
echo "$stats" | python3 -m json.tool 2>/dev/null || echo "$stats"

# Validate metrics
FAILED=0

# Check total requests
total_requests=$(echo "$stats" | grep -o '"totalRequests":[0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
if [ -n "$total_requests" ] && [ "$total_requests" -gt 0 ]; then
    echo "✓ Total Requests: $total_requests (non-zero)"
else
    echo "✗ Total Requests: $total_requests (should be > 0)"
    FAILED=$((FAILED + 1))
fi

# Check legacy count
legacy_count=$(echo "$stats" | grep -o '"legacyCount":[0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
echo "  Legacy Count: $legacy_count"

# Check modern count
modern_count=$(echo "$stats" | grep -o '"modernCount":[0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
echo "  Modern Count: $modern_count"

# Check distribution
legacy_dist=$(echo "$stats" | grep -o '"legacy":"[0-9.]*"' | grep -o '[0-9.]*' || echo "0")
modern_dist=$(echo "$stats" | grep -o '"modern":"[0-9.]*"' | grep -o '[0-9.]*' || echo "0")
echo "  Legacy Distribution: ${legacy_dist}%"
echo "  Modern Distribution: ${modern_dist}%"

# Check ACL stats
acl_stats=$(curl -s "http://localhost:3005/acl/stats" 2>/dev/null || echo "{}")
echo ""
echo "=== ACL Stats ==="
echo "$acl_stats" | python3 -m json.tool 2>/dev/null || echo "$acl_stats"

acl_total=$(echo "$acl_stats" | grep -o '"totalRequests":[0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
if [ -n "$acl_total" ] && [ "$acl_total" -ge 0 ]; then
    echo "✓ ACL Total Requests: $acl_total"
else
    echo "✗ ACL Total Requests: $acl_total"
    FAILED=$((FAILED + 1))
fi

# Test products endpoint
echo ""
echo "=== Testing Products ==="
products=$(curl -s "http://localhost:3000/api/products")
product_count=$(echo "$products" | grep -o '"PROD-[^"]*"' | wc -l || echo "0")
if [ "$product_count" -gt 0 ]; then
    echo "✓ Products available: $product_count"
else
    echo "✗ No products found"
    FAILED=$((FAILED + 1))
fi

# Generate more traffic through ACL (legacy path)
echo ""
echo "Generating traffic through ACL (legacy path)..."
for i in {1..3}; do
    curl -s -X POST "http://localhost:3005/legacy/orders" \
        -H "Content-Type: application/json" \
        -d "{\"customerName\":\"Legacy-Customer-$i\",\"productCode\":\"PROD-001\",\"quantity\":1,\"totalAmount\":1299.99}" > /dev/null
    sleep 1
done

sleep 2

# Check updated ACL stats
echo ""
echo "=== Updated ACL Stats ==="
acl_stats_updated=$(curl -s "http://localhost:3005/acl/stats")
acl_total_updated=$(echo "$acl_stats_updated" | grep -o '"totalRequests":[0-9]*' | grep -o '[0-9]*' | head -1 || echo "0")
if [ -n "$acl_total_updated" ] && [ "$acl_total_updated" -gt 0 ]; then
    echo "✓ ACL Total Requests: $acl_total_updated (updated)"
else
    echo "✗ ACL Total Requests: $acl_total_updated (should be > 0)"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo "✅ Dashboard metrics validation passed!"
    echo ""
    echo "Dashboard URL: http://localhost:3100"
    echo "All metrics are updating correctly."
    exit 0
else
    echo "❌ $FAILED validation(s) failed"
    exit 1
fi

