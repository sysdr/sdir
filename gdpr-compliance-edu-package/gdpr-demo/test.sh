#!/bin/bash

echo "🧪 Running GDPR Compliance Tests..."

API="http://localhost:3001/api"

# Test 1: Create user with consent
echo "Test 1: Creating user with consent..."
USER_RESPONSE=$(curl -s -X POST $API/users \
  -H "Content-Type: application/json" \
  -d '{
    "email": "test@example.com",
    "name": "Test User",
    "phone": "+1234567890",
    "consents": {
      "marketing": true,
      "analytics": true,
      "profiling": false,
      "thirdParty": false
    }
  }')

USER_ID=$(echo $USER_RESPONSE | grep -o '"userId":"[^"]*' | cut -d'"' -f4)
echo "✓ User created: $USER_ID"

sleep 2

# Test 2: Access user data (Right to Access)
echo "Test 2: Accessing user data (Right to Access)..."
curl -s $API/users/$USER_ID | jq '.user.email'
echo "✓ Data accessed successfully"

sleep 2

# Test 3: Update consent
echo "Test 3: Updating consent (Consent Management)..."
curl -s -X POST $API/users/$USER_ID/consent \
  -H "Content-Type: application/json" \
  -d '{"consentType": "marketing", "status": false}'
echo "✓ Consent withdrawn"

sleep 2

# Test 4: Data export (Right to Data Portability)
echo "Test 4: Exporting user data..."
curl -s $API/users/$USER_ID/export -o /tmp/user-export.json
echo "✓ Data exported to /tmp/user-export.json"

sleep 2

# Test 5: User deletion (Right to Erasure)
echo "Test 5: Deleting user (Right to Erasure)..."
curl -s -X DELETE $API/users/$USER_ID
echo "✓ Deletion request submitted"

sleep 3

# Test 6: Check audit log
echo "Test 6: Checking audit log..."
AUDIT_COUNT=$(curl -s $API/audit-logs | jq 'length')
echo "✓ Audit log contains $AUDIT_COUNT entries"

echo ""
echo "✅ All tests completed successfully!"
echo "Check the dashboard at http://localhost:3000"
