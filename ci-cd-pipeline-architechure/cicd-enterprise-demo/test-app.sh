#!/bin/bash

# Don't exit on error - we want to run all tests
# set -e

echo "🧪 Testing CI/CD Pipeline Demo Application"
echo "=========================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0

test_endpoint() {
    local name=$1
    local url=$2
    local expected_status=${3:-200}
    
    echo -n "Testing $name... "
    response=$(curl -s -w "\n%{http_code}" "$url")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" == "$expected_status" ]; then
        echo -e "${GREEN}✓ PASSED${NC}"
        echo "  Response: $(echo "$body" | head -c 100)..."
        ((PASSED++))
        return 0
    else
        echo -e "${RED}✗ FAILED${NC} (HTTP $http_code, expected $expected_status)"
        echo "  Response: $body"
        ((FAILED++))
        return 1
    fi
}

# 1. Test Health Endpoints
echo "1. Health Check Endpoints"
echo "------------------------"
test_endpoint "Orchestrator Health" "http://localhost:3001/health"
test_endpoint "Frontend Health" "http://localhost:8080/health"
test_endpoint "Backend Health" "http://localhost:8081/health"
test_endpoint "Database Health" "http://localhost:8082/health"
echo ""

# 2. Test API Endpoints
echo "2. Pipeline API Endpoints"
echo "-------------------------"
test_endpoint "Get All Pipelines" "http://localhost:3001/api/pipelines"
test_endpoint "Get Metrics" "http://localhost:3001/api/metrics"
test_endpoint "Get Services Status" "http://localhost:3001/api/services"
echo ""

# 3. Test Pipeline Trigger
echo "3. Pipeline Operations"
echo "---------------------"
echo -n "Triggering frontend pipeline... "
TRIGGER_RESPONSE=$(curl -s -X POST http://localhost:3001/api/pipelines/frontend/trigger \
    -H "Content-Type: application/json" \
    -d '{"commit":"test-123","author":"test-user","message":"Test pipeline trigger"}')
PIPELINE_ID=$(echo "$TRIGGER_RESPONSE" | grep -o '"pipelineId":"[^"]*"' | cut -d'"' -f4)

if [ -n "$PIPELINE_ID" ]; then
    echo -e "${GREEN}✓ PASSED${NC}"
    echo "  Pipeline ID: $PIPELINE_ID"
    ((PASSED++))
    
    # Wait a moment for pipeline to start
    sleep 2
    
    # Get pipeline details
    echo -n "Getting pipeline details... "
    PIPELINE_DETAILS=$(curl -s "http://localhost:3001/api/pipelines/$PIPELINE_ID")
    if echo "$PIPELINE_DETAILS" | grep -q '"id"'; then
        echo -e "${GREEN}✓ PASSED${NC}"
        echo "  Status: $(echo "$PIPELINE_DETAILS" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)"
        echo "  Service: $(echo "$PIPELINE_DETAILS" | grep -o '"service":"[^"]*"' | cut -d'"' -f4)"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
    fi
else
    echo -e "${RED}✗ FAILED${NC}"
    echo "  Response: $TRIGGER_RESPONSE"
    ((FAILED++))
fi
echo ""

# 4. Test Metrics Content
echo "4. Metrics Validation"
echo "---------------------"
echo -n "Checking metrics structure... "
METRICS=$(curl -s http://localhost:3001/api/metrics)
if echo "$METRICS" | grep -q '"totalPipelines"'; then
    echo -e "${GREEN}✓ PASSED${NC}"
    TOTAL=$(echo "$METRICS" | grep -o '"totalPipelines":[0-9]*' | cut -d':' -f2)
    SUCCESS=$(echo "$METRICS" | grep -o '"successfulPipelines":[0-9]*' | cut -d':' -f2)
    FAILED_COUNT=$(echo "$METRICS" | grep -o '"failedPipelines":[0-9]*' | cut -d':' -f2)
    echo "  Total Pipelines: $TOTAL"
    echo "  Successful: $SUCCESS"
    echo "  Failed: $FAILED_COUNT"
    ((PASSED++))
else
    echo -e "${RED}✗ FAILED${NC}"
    ((FAILED++))
fi
echo ""

# 5. Test Different Service Pipelines
echo "5. Service-Specific Pipelines"
echo "------------------------------"
for service in frontend backend database; do
    echo -n "Triggering $service pipeline... "
    RESPONSE=$(curl -s -X POST "http://localhost:3001/api/pipelines/$service/trigger" \
        -H "Content-Type: application/json" \
        -d "{\"commit\":\"test-$service\",\"author\":\"test\",\"message\":\"Test $service pipeline\"}")
    if echo "$RESPONSE" | grep -q '"pipelineId"'; then
        echo -e "${GREEN}✓ PASSED${NC}"
        ((PASSED++))
    else
        echo -e "${RED}✗ FAILED${NC}"
        ((FAILED++))
    fi
done
echo ""

# Summary
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo -e "${GREEN}Passed: $PASSED${NC}"
if [ $FAILED -gt 0 ]; then
    echo -e "${RED}Failed: $FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}Failed: $FAILED${NC}"
    echo ""
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
fi

