#!/bin/bash

# Two-Phase Commit Test Scenarios
echo "🧪 Running Two-Phase Commit Test Scenarios"

COORDINATOR_URL="http://localhost:8000"

# Test 1: Successful transaction
echo "📋 Test 1: Successful Transaction"
TRANSACTION_ID=$(curl -s -X POST "$COORDINATOR_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "participants": ["payment-service", "inventory-service", "shipping-service"],
    "operation_data": {
      "amount": 100,
      "product": "laptop",
      "quantity": 1,
      "shipping_address": "123 Test Street"
    }
  }' | jq -r '.transaction_id')

echo "Started transaction: $TRANSACTION_ID"

# Monitor transaction
for i in {1..30}; do
  STATUS=$(curl -s "$COORDINATOR_URL/transaction/$TRANSACTION_ID" | jq -r '.state')
  echo "  Status: $STATUS"
  
  if [ "$STATUS" = "committed" ] || [ "$STATUS" = "aborted" ]; then
    break
  fi
  
  sleep 1
done

echo "Final status: $STATUS"
echo ""

# Test 2: Transaction with high amount (should fail)
echo "📋 Test 2: High Amount Transaction (Expected Failure)"
TRANSACTION_ID=$(curl -s -X POST "$COORDINATOR_URL/transaction" \
  -H "Content-Type: application/json" \
  -d '{
    "participants": ["payment-service", "inventory-service", "shipping-service"],
    "operation_data": {
      "amount": 50000,
      "product": "laptop",
      "quantity": 100,
      "shipping_address": "123 Test Street"
    }
  }' | jq -r '.transaction_id')

echo "Started transaction: $TRANSACTION_ID"

# Monitor transaction
for i in {1..30}; do
  STATUS=$(curl -s "$COORDINATOR_URL/transaction/$TRANSACTION_ID" | jq -r '.state')
  echo "  Status: $STATUS"
  
  if [ "$STATUS" = "committed" ] || [ "$STATUS" = "aborted" ]; then
    break
  fi
  
  sleep 1
done

echo "Final status: $STATUS"
echo ""

# Test 3: System status
echo "📋 Test 3: System Status"
curl -s "$COORDINATOR_URL/status" | jq '.'

echo ""
echo "✅ Test scenarios completed!"
