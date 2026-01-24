#!/bin/bash

echo "🎬 Running Global Payment System Demo..."
echo ""
echo "Generating sample payments across multiple regions and currencies..."
echo ""

CURRENCIES=("USD" "EUR" "GBP" "JPY" "INR")

for i in {1..10}; do
  SOURCE_CURRENCY=${CURRENCIES[$RANDOM % ${#CURRENCIES[@]}]}
  TARGET_CURRENCY=${CURRENCIES[$RANDOM % ${#CURRENCIES[@]}]}
  
  while [ "$SOURCE_CURRENCY" == "$TARGET_CURRENCY" ]; do
    TARGET_CURRENCY=${CURRENCIES[$RANDOM % ${#CURRENCIES[@]}]}
  done
  
  AMOUNT=$((RANDOM % 10000 + 100))
  
  echo "Payment $i: $AMOUNT $SOURCE_CURRENCY → $TARGET_CURRENCY"
  
  RESPONSE=$(curl -s -X POST http://localhost:3000/api/payment \
    -H "Content-Type: application/json" \
    -d "{
      \"amount\": $AMOUNT,
      \"sourceCurrency\": \"$SOURCE_CURRENCY\",
      \"targetCurrency\": \"$TARGET_CURRENCY\"
    }")
  
  if command -v jq &> /dev/null; then
    STATE=$(echo "$RESPONSE" | jq -r '.state')
    echo "  State: $STATE"
  else
    STATE=$(echo "$RESPONSE" | grep -o '"state":"[^"]*"' | cut -d'"' -f4)
    echo "  State: $STATE"
  fi
  
  sleep 1
done

echo ""
echo "✅ Demo completed! Check the dashboard at http://localhost:3002"
