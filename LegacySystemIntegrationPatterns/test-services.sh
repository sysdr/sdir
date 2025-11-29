#!/bin/bash

set -e

echo "=========================================="
echo "Testing Legacy Integration Services"
echo "=========================================="
echo ""

FAILED=0

# Test function
test_endpoint() {
    local name=$1
    local url=$2
    local expected_status=${3:-200}
    
    echo -n "Testing $name... "
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" || echo "000")
    
    if [ "$response" = "$expected_status" ]; then
        echo "✓ PASS"
        return 0
    else
        echo "✗ FAIL (got $response, expected $expected_status)"
        FAILED=$((FAILED + 1))
        return 1
    fi
}

# Test health endpoints
echo "=== Health Checks ==="
test_endpoint "Legacy Service" "http://localhost:3001/health"
test_endpoint "Product Service" "http://localhost:3002/health"
test_endpoint "Order Service" "http://localhost:3003/health"
test_endpoint "Payment Service" "http://localhost:3004/health"
test_endpoint "ACL Service" "http://localhost:3005/health"
test_endpoint "Strangler Proxy" "http://localhost:3000/health"
test_endpoint "Event Bus" "http://localhost:3006/health"
test_endpoint "Dashboard" "http://localhost:3100"

echo ""
echo "=== API Tests ==="

# Test products endpoint
echo -n "Testing Products API... "
products=$(curl -s "http://localhost:3000/api/products" || echo "{}")
if echo "$products" | grep -q "products"; then
    echo "✓ PASS"
else
    echo "✗ FAIL"
    FAILED=$((FAILED + 1))
fi

# Test stats endpoint
echo -n "Testing Stats API... "
stats=$(curl -s "http://localhost:3000/api/stats" || echo "{}")
if echo "$stats" | grep -q "traffic"; then
    echo "✓ PASS"
else
    echo "✗ FAIL"
    FAILED=$((FAILED + 1))
fi

# Test creating an order
echo -n "Testing Order Creation... "
order_response=$(curl -s -X POST "http://localhost:3000/api/orders" \
    -H "Content-Type: application/json" \
    -d '{"customerName":"Test Customer","productCode":"PROD-001","quantity":1,"totalAmount":1299.99}' || echo "{}")
if echo "$order_response" | grep -q "orderId\|id"; then
    echo "✓ PASS"
else
    echo "✗ FAIL"
    FAILED=$((FAILED + 1))
fi

echo ""
echo "=========================================="
if [ $FAILED -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ $FAILED test(s) failed"
    exit 1
fi

