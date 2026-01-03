#!/bin/bash

echo "Running integration tests..."

BASE_URL="http://localhost:3002"
QUERY_URL="http://localhost:3003"

# Wait for services
sleep 5

# Test 1: Create account
echo "Test 1: Create account..."
ACCOUNT_ID="test-$(date +%s)"
curl -s -X POST ${BASE_URL}/commands/create-account \
  -H "Content-Type: application/json" \
  -d "{\"accountId\":\"${ACCOUNT_ID}\",\"initialBalance\":1000}" | grep -q "success"

if [ $? -eq 0 ]; then
  echo "✅ Account created"
else
  echo "❌ Account creation failed"
  exit 1
fi

# Wait for projection
sleep 5

# Test 2: Query account
echo "Test 2: Query account..."
BALANCE=$(curl -s ${QUERY_URL}/accounts/${ACCOUNT_ID} | grep -o '"balance":[0-9.]*' | cut -d: -f2)
if [ "$BALANCE" = "1000" ]; then
  echo "✅ Balance correct: $BALANCE"
else
  echo "❌ Balance incorrect: $BALANCE (expected 1000)"
  exit 1
fi

# Test 3: Deposit
echo "Test 3: Deposit money..."
curl -s -X POST ${BASE_URL}/commands/deposit \
  -H "Content-Type: application/json" \
  -d "{\"accountId\":\"${ACCOUNT_ID}\",\"amount\":500}" | grep -q "success"

if [ $? -eq 0 ]; then
  echo "✅ Deposit successful"
else
  echo "❌ Deposit failed"
  exit 1
fi

# Wait for projection
sleep 5

# Test 4: Verify new balance
echo "Test 4: Verify new balance..."
BALANCE=$(curl -s ${QUERY_URL}/accounts/${ACCOUNT_ID} | grep -o '"balance":[0-9.]*' | cut -d: -f2)
if [ "$BALANCE" = "1500" ]; then
  echo "✅ Balance correct: $BALANCE"
else
  echo "❌ Balance incorrect: $BALANCE (expected 1500)"
  exit 1
fi

# Test 5: Withdraw
echo "Test 5: Withdraw money..."
curl -s -X POST ${BASE_URL}/commands/withdraw \
  -H "Content-Type: application/json" \
  -d "{\"accountId\":\"${ACCOUNT_ID}\",\"amount\":200}" | grep -q "success"

if [ $? -eq 0 ]; then
  echo "✅ Withdrawal successful"
else
  echo "❌ Withdrawal failed"
  exit 1
fi

# Wait for projection
sleep 5

# Test 6: Final balance
echo "Test 6: Verify final balance..."
BALANCE=$(curl -s ${QUERY_URL}/accounts/${ACCOUNT_ID} | grep -o '"balance":[0-9.]*' | cut -d: -f2)
if [ "$BALANCE" = "1300" ]; then
  echo "✅ Balance correct: $BALANCE"
else
  echo "❌ Balance incorrect: $BALANCE (expected 1300)"
  exit 1
fi

echo ""
echo "✅ All tests passed!"
