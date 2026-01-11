#!/bin/bash
# Test script for microservice architectures

echo "=== Running Tests ==="
echo ""

ERRORS=0

# Test function
test_endpoint() {
    local name=$1
    local url=$2
    local expected_status=${3:-200}
    
    echo "Testing $name..."
    response=$(curl -s -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
    
    if [ "$response" = "$expected_status" ]; then
        echo "  ✅ $name: OK (HTTP $response)"
        return 0
    else
        echo "  ❌ $name: FAILED (HTTP $response, expected $expected_status)"
        ((ERRORS++))
        return 1
    fi
}

# Test health endpoints
echo "Testing health endpoints..."
test_endpoint "Monolith Health" "http://localhost:3001/health"
test_endpoint "Order Service Health" "http://localhost:3002/health"
test_endpoint "Payment Service Health" "http://localhost:3003/health"
test_endpoint "Inventory Service Health" "http://localhost:3004/health"
test_endpoint "Strangler Gateway Health" "http://localhost:3005/health"
test_endpoint "Legacy Monolith Health" "http://localhost:3006/health"
test_endpoint "New Payment Service Health" "http://localhost:3007/health"

echo ""
echo "Testing metrics endpoints..."
test_endpoint "Monolith Metrics" "http://localhost:3001/api/monolith/metrics"
test_endpoint "Order Service Metrics" "http://localhost:3002/api/orders/metrics"
test_endpoint "Payment Service Metrics" "http://localhost:3003/api/payments/metrics"
test_endpoint "Inventory Service Metrics" "http://localhost:3004/api/inventory/metrics"
test_endpoint "Strangler Gateway Metrics" "http://localhost:3005/api/strangler/metrics"

echo ""
echo "Testing order creation endpoints..."
echo "Testing Monolith order creation..."
MONO_RESPONSE=$(curl -s -X POST http://localhost:3001/api/monolith/order \
    -H "Content-Type: application/json" \
    -d '{"productId":"PROD-001","quantity":1}' 2>/dev/null)
if echo "$MONO_RESPONSE" | grep -q "order"; then
    echo "  ✅ Monolith order creation: OK"
else
    echo "  ❌ Monolith order creation: FAILED"
    ((ERRORS++))
fi

echo "Testing Microservices order creation..."
MICRO_RESPONSE=$(curl -s -X POST http://localhost:3002/api/orders \
    -H "Content-Type: application/json" \
    -d '{"productId":"PROD-001","quantity":1}' 2>/dev/null)
if echo "$MICRO_RESPONSE" | grep -q "order"; then
    echo "  ✅ Microservices order creation: OK"
else
    echo "  ❌ Microservices order creation: FAILED"
    ((ERRORS++))
fi

echo "Testing Strangler order creation..."
STRANG_RESPONSE=$(curl -s -X POST http://localhost:3005/api/strangler/order \
    -H "Content-Type: application/json" \
    -d '{"productId":"PROD-001","quantity":1}' 2>/dev/null)
if echo "$STRANG_RESPONSE" | grep -q "order"; then
    echo "  ✅ Strangler order creation: OK"
else
    echo "  ❌ Strangler order creation: FAILED"
    ((ERRORS++))
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ $ERRORS test(s) failed!"
    exit 1
fi

