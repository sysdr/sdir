#!/bin/bash

# Zero-Trust Security Architecture - Demo Script
# This script generates activity to test the dashboard metrics

set -e

echo "=================================="
echo "Zero-Trust Architecture Demo"
echo "=================================="
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to make authenticated request
make_request() {
    local endpoint=$1
    local token=$2
    local description=$3
    
    echo -e "${BLUE}Testing: $description${NC}"
    response=$(curl -s -w "\n%{http_code}" "http://localhost:3003$endpoint" \
        -H "Authorization: Bearer $token")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" = "200" ]; then
        echo -e "${GREEN}✓ Access granted (HTTP $http_code)${NC}"
        echo "$body" | python3 -m json.tool 2>/dev/null | head -3 || echo "$body" | head -3
    else
        echo -e "✗ Access denied (HTTP $http_code)"
        echo "$body" | head -3
    fi
    echo ""
}

# Step 1: Login as Alice (Engineer)
echo "Step 1: Authenticating as alice@company.com (Engineer, device-001)..."
login_response=$(curl -s -X POST http://localhost:3001/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"alice@company.com","password":"password123","deviceId":"device-001","location":{"city":"San Francisco"}}')

if echo "$login_response" | grep -q "accessToken"; then
    alice_token=$(echo "$login_response" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    echo -e "${GREEN}✓ Authentication successful${NC}"
    echo ""
else
    echo "✗ Authentication failed"
    echo "$login_response"
    exit 1
fi

# Step 2: Make various API requests
echo "Step 2: Testing API endpoints..."
echo ""

make_request "/api/public" "$alice_token" "Public API (should be allowed)"
make_request "/api/database" "$alice_token" "Database API (should be allowed for engineer)"
make_request "/api/users" "$alice_token" "Users API (should be denied - requires admin)"

# Step 3: Login as Bob (Admin)
echo "Step 3: Authenticating as bob@company.com (Admin, device-002)..."
bob_response=$(curl -s -X POST http://localhost:3001/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"bob@company.com","password":"password456","deviceId":"device-002","location":{"city":"New York"}}')

if echo "$bob_response" | grep -q "accessToken"; then
    bob_token=$(echo "$bob_response" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
    echo -e "${GREEN}✓ Authentication successful${NC}"
    echo ""
else
    echo "✗ Authentication failed"
    echo "$bob_response"
    exit 1
fi

# Step 4: Test admin access
echo "Step 4: Testing admin access..."
echo ""

make_request "/api/users" "$bob_token" "Users API (should be allowed for admin)"
make_request "/api/database" "$bob_token" "Database API (should be allowed for admin)"

# Step 5: Test device posture rejection
echo "Step 5: Testing device posture check (insecure device)..."
insecure_response=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3001/auth/login \
    -H "Content-Type: application/json" \
    -d '{"email":"alice@company.com","password":"password123","deviceId":"device-003","location":{"city":"SF"}}')

http_code=$(echo "$insecure_response" | tail -n1)
if [ "$http_code" = "403" ]; then
    echo -e "${GREEN}✓ Insecure device correctly rejected (HTTP 403)${NC}"
else
    echo "✗ Device posture check failed (expected HTTP 403, got $http_code)"
fi
echo ""

# Step 6: Display current metrics
echo "=================================="
echo "Current Metrics"
echo "=================================="
echo ""

echo "Proxy Statistics:"
curl -s http://localhost:3003/proxy/stats | python3 -m json.tool | grep -E "(totalRequests|allowed|denied|avgLatency)" | head -4
echo ""

echo "Policy Decisions:"
curl -s http://localhost:3002/policy/decisions | python3 -m json.tool | grep -E "(total|allowed|denied)" | head -3
echo ""

echo "Active Sessions:"
curl -s http://localhost:3001/auth/sessions | python3 -m json.tool | grep "count"
echo ""

echo "=================================="
echo "Demo completed!"
echo "=================================="
echo ""
echo "Dashboard: http://localhost:3000"
echo "All metrics should be updated and non-zero."
echo ""

