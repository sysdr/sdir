#!/bin/bash

echo "=================================="
echo "Running Zero-Trust Architecture Tests"
echo "=================================="

# Wait for services
echo "Waiting for services to be ready..."
sleep 15

# Test 1: Identity Provider
echo -e "\n[Test 1] Testing Identity Provider authentication..."
response=$(curl -s -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@company.com","password":"password123","deviceId":"device-001","location":{"city":"SF"}}')

if echo "$response" | grep -q "accessToken"; then
  echo "✓ Identity authentication successful"
  token=$(echo "$response" | grep -o '"accessToken":"[^"]*' | cut -d'"' -f4)
else
  echo "✗ Identity authentication failed"
  exit 1
fi

# Test 2: Token validation
echo -e "\n[Test 2] Testing token validation..."
response=$(curl -s -X POST http://localhost:3001/auth/validate \
  -H "Content-Type: application/json" \
  -d "{\"token\":\"$token\"}")

if echo "$response" | grep -q '"valid":true'; then
  echo "✓ Token validation successful"
else
  echo "✗ Token validation failed"
  exit 1
fi

# Test 3: Policy evaluation
echo -e "\n[Test 3] Testing policy engine..."
response=$(curl -s http://localhost:3002/policy/list)

if echo "$response" | grep -q "policies"; then
  echo "✓ Policy engine responding"
else
  echo "✗ Policy engine failed"
  exit 1
fi

# Test 4: Access proxy with valid auth
echo -e "\n[Test 4] Testing access proxy with authentication..."
response=$(curl -s -w "\n%{http_code}" http://localhost:3003/api/public \
  -H "Authorization: Bearer $token")

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "200" ]; then
  echo "✓ Access proxy granted access"
else
  echo "✗ Access proxy test failed (HTTP $http_code)"
  exit 1
fi

# Test 5: Access proxy without auth
echo -e "\n[Test 5] Testing access proxy without authentication..."
response=$(curl -s -w "\n%{http_code}" http://localhost:3003/api/public)

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "401" ]; then
  echo "✓ Access proxy correctly denied unauthenticated request"
else
  echo "✗ Access proxy should have denied request"
  exit 1
fi

# Test 6: Device posture check
echo -e "\n[Test 6] Testing device posture check (insecure device)..."
response=$(curl -s -w "\n%{http_code}" -X POST http://localhost:3001/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"alice@company.com","password":"password123","deviceId":"device-003","location":{"city":"SF"}}')

http_code=$(echo "$response" | tail -n1)
if [ "$http_code" = "403" ]; then
  echo "✓ Insecure device correctly rejected"
else
  echo "✗ Device posture check failed"
  exit 1
fi

# Test 7: Policy decision logging
echo -e "\n[Test 7] Testing policy decision logging..."
response=$(curl -s http://localhost:3002/policy/decisions)

if echo "$response" | grep -q "decisions"; then
  echo "✓ Policy decisions being logged"
else
  echo "✗ Policy logging failed"
  exit 1
fi

# Test 8: Active sessions tracking
echo -e "\n[Test 8] Testing active sessions..."
response=$(curl -s http://localhost:3001/auth/sessions)

if echo "$response" | grep -q "sessions"; then
  echo "✓ Session tracking operational"
else
  echo "✗ Session tracking failed"
  exit 1
fi

echo -e "\n=================================="
echo "All tests passed! ✓"
echo "=================================="
echo ""
echo "Access the dashboard at: http://localhost:3000"
echo ""
echo "Try these scenarios:"
echo "1. Login with alice@company.com using device-001 (secure)"
echo "2. Access different endpoints (/api/database, /api/users, /api/public)"
echo "3. Try device-003 (insecure) and observe rejection"
echo "4. Watch policy decisions and proxy statistics update in real-time"
