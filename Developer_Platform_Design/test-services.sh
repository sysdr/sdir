#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_PLATFORM_DIR="${SCRIPT_DIR}/dev-platform"

echo "======================================"
echo "Testing Developer Platform Services"
echo "======================================"

# Test functions
test_endpoint() {
    local name=$1
    local url=$2
    local expected_status=${3:-200}
    
    echo -n "Testing ${name}... "
    response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null || echo -e "\n000")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "$expected_status" ]; then
        echo "✅ PASS (HTTP $http_code)"
        return 0
    else
        echo "❌ FAIL (HTTP $http_code, expected $expected_status)"
        return 1
    fi
}

test_metrics_not_zero() {
    local metric_name=$1
    local value=$2
    
    if [ -z "$value" ] || [ "$value" = "0" ] || [ "$value" = "0.0" ] || [ "$value" = "0.00" ]; then
        echo "❌ FAIL: ${metric_name} is zero or empty"
        return 1
    else
        echo "✅ PASS: ${metric_name} = ${value}"
        return 0
    fi
}

# Check if services are running
echo ""
echo "Checking if services are running..."
cd "$DEV_PLATFORM_DIR" 2>/dev/null || {
    echo "❌ Error: dev-platform directory not found!"
    exit 1
}

RUNNING=$(docker-compose ps --services --filter "status=running" 2>/dev/null | wc -l)
if [ "$RUNNING" -lt 4 ]; then
    echo "❌ Error: Not all services are running. Found $RUNNING/4 services."
    echo "Please run start-services.sh first."
    exit 1
fi

echo "✅ All services are running"
echo ""

# Test 1: Health endpoints
echo "=== Testing Health Endpoints ==="
test_endpoint "Catalog Health" "http://localhost:3001/health"
test_endpoint "Deployer Health" "http://localhost:3002/health"
test_endpoint "Metrics Health" "http://localhost:3003/health"
echo ""

# Test 2: Service Catalog API
echo "=== Testing Service Catalog API ==="
test_endpoint "Get Services" "http://localhost:3001/api/services"
SERVICES=$(curl -s "http://localhost:3001/api/services")
SERVICE_COUNT=$(echo "$SERVICES" | grep -o '"id"' | wc -l)
if [ "$SERVICE_COUNT" -gt 0 ]; then
    echo "✅ PASS: Found $SERVICE_COUNT services"
else
    echo "❌ FAIL: No services found"
    exit 1
fi
echo ""

# Test 3: Deployments API
echo "=== Testing Deployments API ==="
test_endpoint "Get Deployments" "http://localhost:3002/api/deployments"
echo ""

# Test 4: Metrics API
echo "=== Testing Metrics API ==="
test_endpoint "Get Metrics" "http://localhost:3003/api/metrics"
METRICS=$(curl -s "http://localhost:3003/api/metrics")

# Extract metric values
TOTAL_SERVICES=$(echo "$METRICS" | grep -o '"totalServices":[0-9]*' | grep -o '[0-9]*')
HEALTHY_SERVICES=$(echo "$METRICS" | grep -o '"healthyServices":[0-9]*' | grep -o '[0-9]*')
REQUESTS_PER_SEC=$(echo "$METRICS" | grep -o '"requestsPerSecond":[0-9]*' | grep -o '[0-9]*')
ERROR_RATE=$(echo "$METRICS" | grep -o '"errorRate":"[^"]*"' | cut -d'"' -f4)

echo ""
echo "=== Validating Metrics (should not be zero) ==="
test_metrics_not_zero "Total Services" "$TOTAL_SERVICES"
test_metrics_not_zero "Healthy Services" "$HEALTHY_SERVICES"
test_metrics_not_zero "Requests Per Second" "$REQUESTS_PER_SEC"
test_metrics_not_zero "Error Rate" "$ERROR_RATE"
echo ""

# Test 5: Trigger a deployment to update metrics
echo "=== Testing Deployment Trigger ==="
echo "Triggering a test deployment..."
DEPLOY_RESPONSE=$(curl -s -X POST "http://localhost:3002/api/deploy" \
    -H "Content-Type: application/json" \
    -d '{"service":"api-gateway","version":"v2.4.0","strategy":"rolling"}')

if echo "$DEPLOY_RESPONSE" | grep -q "deploymentId"; then
    echo "✅ PASS: Deployment triggered successfully"
    DEPLOYMENT_ID=$(echo "$DEPLOY_RESPONSE" | grep -o '"deploymentId":[0-9]*' | grep -o '[0-9]*')
    echo "   Deployment ID: $DEPLOYMENT_ID"
else
    echo "❌ FAIL: Failed to trigger deployment"
    echo "Response: $DEPLOY_RESPONSE"
    exit 1
fi

# Wait for deployment to progress
echo "Waiting for deployment to progress..."
sleep 5

# Check deployment status
DEPLOYMENT=$(curl -s "http://localhost:3002/api/deployments/${DEPLOYMENT_ID}")
if echo "$DEPLOYMENT" | grep -q '"status"'; then
    echo "✅ PASS: Deployment status retrieved"
else
    echo "❌ FAIL: Could not retrieve deployment status"
    exit 1
fi
echo ""

# Test 6: Verify metrics updated after deployment
echo "=== Verifying Metrics Updated After Deployment ==="
sleep 3
UPDATED_METRICS=$(curl -s "http://localhost:3003/api/metrics")
UPDATED_TOTAL_DEPLOYMENTS=$(echo "$UPDATED_METRICS" | grep -o '"totalDeployments":[0-9]*' | grep -o '[0-9]*')
UPDATED_ACTIVE_DEPLOYMENTS=$(echo "$UPDATED_METRICS" | grep -o '"activeDeployments":[0-9]*' | grep -o '[0-9]*')

if [ -n "$UPDATED_TOTAL_DEPLOYMENTS" ] && [ "$UPDATED_TOTAL_DEPLOYMENTS" -gt 0 ]; then
    echo "✅ PASS: Total deployments updated: $UPDATED_TOTAL_DEPLOYMENTS"
else
    echo "⚠️  WARNING: Total deployments may not have updated"
fi

echo ""
echo "======================================"
echo "✅ All tests completed!"
echo "======================================"
echo ""
echo "Metrics Summary:"
echo "  Total Services: $TOTAL_SERVICES"
echo "  Healthy Services: $HEALTHY_SERVICES"
echo "  Requests/sec: $REQUESTS_PER_SEC"
echo "  Error Rate: $ERROR_RATE%"
echo "  Total Deployments: $UPDATED_TOTAL_DEPLOYMENTS"
echo "  Active Deployments: $UPDATED_ACTIVE_DEPLOYMENTS"
echo ""

