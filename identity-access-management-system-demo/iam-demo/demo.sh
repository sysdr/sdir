#!/bin/bash

# IAM Demo Script - Complete OAuth 2.0 Flow
# This script demonstrates the full OAuth 2.0 authorization code flow

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

AUTH_SERVER="http://localhost:3001"
RESOURCE_SERVER="http://localhost:3002"

echo "=========================================="
echo "IAM Demo - OAuth 2.0 Authorization Flow"
echo "=========================================="
echo ""

# Check services are running
echo "🔍 Checking services..."
if ! curl -s "$AUTH_SERVER/health" >/dev/null 2>&1; then
    echo "❌ Error: Auth server is not responding at $AUTH_SERVER"
    echo "   Please run './start.sh' first"
    exit 1
fi

if ! curl -s "$RESOURCE_SERVER/health" >/dev/null 2>&1; then
    echo "❌ Error: Resource server is not responding at $RESOURCE_SERVER"
    echo "   Please run './start.sh' first"
    exit 1
fi

echo "✅ Services are running"
echo ""

# Step 1: Request Authorization Code
echo "=========================================="
echo "Step 1: Request Authorization Code"
echo "=========================================="
echo "Requesting authorization code..."
AUTH_RESPONSE=$(curl -s -X GET \
  "$AUTH_SERVER/oauth/authorize?client_id=demo-client&redirect_uri=http://localhost:8080/callback&response_type=code&scope=read&state=xyz123")

echo "Response:"
echo "$AUTH_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$AUTH_RESPONSE"
echo ""

# Extract authorization code
AUTH_CODE=$(echo "$AUTH_RESPONSE" | grep -o '"redirect_to":"[^"]*code=\([^&"]*\)' | sed 's/.*code=\([^&"]*\).*/\1/' || echo "")
if [ -z "$AUTH_CODE" ]; then
    # Try alternative extraction
    AUTH_CODE=$(echo "$AUTH_RESPONSE" | python3 -c "import sys, json, re; data=sys.stdin.read(); m=re.search(r'code=([^&\"]+)', data); print(m.group(1) if m else '')" 2>/dev/null || echo "")
fi

if [ -z "$AUTH_CODE" ]; then
    echo "⚠️  Could not extract authorization code automatically"
    echo "   Please extract the 'code' parameter from the redirect_to URL above"
    read -p "Enter authorization code: " AUTH_CODE
fi

echo "✅ Authorization code: ${AUTH_CODE:0:20}..."
echo ""

# Step 2: Exchange Code for Tokens
echo "=========================================="
echo "Step 2: Exchange Code for Tokens"
echo "=========================================="
echo "Exchanging authorization code for tokens..."
TOKEN_RESPONSE=$(curl -s -X POST "$AUTH_SERVER/oauth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=authorization_code" \
  -d "code=$AUTH_CODE" \
  -d "client_id=demo-client" \
  -d "client_secret=demo-secret" \
  -d "redirect_uri=http://localhost:8080/callback")

echo "Response:"
echo "$TOKEN_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$TOKEN_RESPONSE"
echo ""

# Extract tokens
ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"access_token":"[^"]*"' | sed 's/"access_token":"\([^"]*\)"/\1/' || echo "")
REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"refresh_token":"[^"]*"' | sed 's/"refresh_token":"\([^"]*\)"/\1/' || echo "")

if [ -z "$ACCESS_TOKEN" ]; then
    ACCESS_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
fi
if [ -z "$REFRESH_TOKEN" ]; then
    REFRESH_TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('refresh_token', ''))" 2>/dev/null || echo "")
fi

if [ -z "$ACCESS_TOKEN" ]; then
    echo "❌ Error: Could not extract access token"
    exit 1
fi

echo "✅ Access token obtained: ${ACCESS_TOKEN:0:30}..."
if [ ! -z "$REFRESH_TOKEN" ]; then
    echo "✅ Refresh token obtained: ${REFRESH_TOKEN:0:30}..."
fi
echo ""

# Step 3: Access Protected Resource
echo "=========================================="
echo "Step 3: Access Protected Resource"
echo "=========================================="
echo "Accessing protected documents endpoint..."
DOCS_RESPONSE=$(curl -s -X GET "$RESOURCE_SERVER/api/documents" \
  -H "Authorization: Bearer $ACCESS_TOKEN")

echo "Response:"
echo "$DOCS_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$DOCS_RESPONSE"
echo ""

if echo "$DOCS_RESPONSE" | grep -q "documents"; then
    echo "✅ Successfully accessed protected resource!"
else
    echo "⚠️  Unexpected response"
fi
echo ""

# Step 4: Test Write Permission
echo "=========================================="
echo "Step 4: Test Write Permission"
echo "=========================================="
echo "Testing document creation (requires write permission)..."
WRITE_RESPONSE=$(curl -s -X POST "$RESOURCE_SERVER/api/documents" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"title": "Demo Document"}')

echo "Response:"
echo "$WRITE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$WRITE_RESPONSE"
echo ""

# Step 5: Test Public Endpoint
echo "=========================================="
echo "Step 5: Test Public Endpoint"
echo "=========================================="
echo "Accessing public endpoint (no auth required)..."
PUBLIC_RESPONSE=$(curl -s -X GET "$RESOURCE_SERVER/api/public/info")
echo "Response:"
echo "$PUBLIC_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$PUBLIC_RESPONSE"
echo ""

# Step 6: Token Revocation Demo
if [ ! -z "$ACCESS_TOKEN" ]; then
    echo "=========================================="
    echo "Step 6: Token Revocation"
    echo "=========================================="
    echo "Revoking access token..."
    REVOKE_RESPONSE=$(curl -s -X POST "$AUTH_SERVER/oauth/revoke" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "token=$ACCESS_TOKEN" \
      -d "token_type_hint=access_token")
    
    echo "Response:"
    echo "$REVOKE_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$REVOKE_RESPONSE"
    echo ""
    
    echo "Testing revoked token (should fail)..."
    REVOKED_TEST=$(curl -s -X GET "$RESOURCE_SERVER/api/documents" \
      -H "Authorization: Bearer $ACCESS_TOKEN")
    
    if echo "$REVOKED_TEST" | grep -qi "revoked\|invalid\|unauthorized"; then
        echo "✅ Token revocation working correctly!"
    else
        echo "⚠️  Token still accepted (may be expected behavior)"
    fi
    echo ""
fi

# Step 7: Refresh Token Flow
if [ ! -z "$REFRESH_TOKEN" ]; then
    echo "=========================================="
    echo "Step 7: Refresh Token Flow"
    echo "=========================================="
    echo "Refreshing access token..."
    REFRESH_RESPONSE=$(curl -s -X POST "$AUTH_SERVER/oauth/token" \
      -H "Content-Type: application/x-www-form-urlencoded" \
      -d "grant_type=refresh_token" \
      -d "refresh_token=$REFRESH_TOKEN" \
      -d "client_id=demo-client" \
      -d "client_secret=demo-secret")
    
    echo "Response:"
    echo "$REFRESH_RESPONSE" | python3 -m json.tool 2>/dev/null || echo "$REFRESH_RESPONSE"
    echo ""
    
    NEW_ACCESS_TOKEN=$(echo "$REFRESH_RESPONSE" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('access_token', ''))" 2>/dev/null || echo "")
    if [ ! -z "$NEW_ACCESS_TOKEN" ]; then
        echo "✅ New access token obtained!"
    fi
    echo ""
fi

echo "=========================================="
echo "✅ Demo Complete!"
echo "=========================================="
echo ""
echo "📊 Run './dashboard.sh' to view system metrics"

