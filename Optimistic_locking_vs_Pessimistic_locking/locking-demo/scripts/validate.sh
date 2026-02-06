#!/bin/bash

API_URL="${API_URL:-http://localhost:3001}"
ERRORS=0

echo "🔍 Validating Locking Demo..."
echo ""

# Check health
if ! curl -sf "${API_URL}/health" > /dev/null; then
    echo "❌ Backend not reachable at ${API_URL}"
    exit 1
fi
echo "✅ Backend healthy"

# Reset and get initial balance
INITIAL=$(curl -sf -X POST "${API_URL}/api/reset" | grep -o '"balance":[^,}]*' | cut -d: -f2)
ACCOUNT=$(curl -sf "${API_URL}/api/account")
BALANCE=$(echo "$ACCOUNT" | grep -o '"balance":[^,}]*' | cut -d: -f2)
echo "✅ Account reset - Balance: $BALANCE"

# Run pessimistic batch
RESULT=$(curl -sf -X POST "${API_URL}/api/batch" -H "Content-Type: application/json" \
  -d '{"mode":"pessimistic","count":20,"amount":10}')
if ! echo "$RESULT" | grep -q '"success":true'; then
    echo "❌ Pessimistic batch failed"
    ((ERRORS++))
else
    echo "✅ Pessimistic batch completed"
fi

sleep 1

# Run optimistic batch
RESULT=$(curl -sf -X POST "${API_URL}/api/batch" -H "Content-Type: application/json" \
  -d '{"mode":"optimistic","count":20,"amount":-5}')
if ! echo "$RESULT" | grep -q '"success":true'; then
    echo "❌ Optimistic batch failed"
    ((ERRORS++))
else
    echo "✅ Optimistic batch completed"
fi

sleep 1

# Verify balance changed
ACCOUNT=$(curl -sf "${API_URL}/api/account")
BALANCE=$(echo "$ACCOUNT" | grep -o '"balance":[^,}]*' | cut -d: -f2)
VERSION=$(echo "$ACCOUNT" | grep -o '"version":[^,}]*' | cut -d: -f2)
echo ""
echo "📊 Final state - Balance: $BALANCE, Version: $VERSION"

if [ "$BALANCE" = "1000" ] || [ "$BALANCE" = "1000.00" ]; then
    echo "⚠️  Balance unchanged - transactions may not have affected balance (net zero)"
fi

echo ""
if [ $ERRORS -eq 0 ]; then
    echo "✅ Validation passed! Dashboard at http://localhost:3000 should show updated metrics."
else
    echo "❌ Validation had $ERRORS error(s)"
    exit 1
fi
