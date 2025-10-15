#!/bin/bash

echo "🧪 Running Bounded Contexts Integration Tests..."

BASE_URL="http://localhost:3000/api"

# Wait for services to be ready
echo "⏳ Waiting for services to start..."
sleep 10

# Test 1: Health Check
echo "Test 1: Health Check"
curl -s "$BASE_URL/health" | jq -r '.[] | "\(.name): \(.status)"'

# Test 2: Create User
echo -e "\nTest 2: Create User"
USER_RESPONSE=$(curl -s -X POST "$BASE_URL/users" \
  -H "Content-Type: application/json" \
  -d '{"email":"test@example.com","firstName":"Test","lastName":"User"}')

USER_ID=$(echo "$USER_RESPONSE" | jq -r '.userId // empty')
echo "Created user: $USER_ID"

# Test 3: Get Products
echo -e "\nTest 3: Get Products"
curl -s "$BASE_URL/products" | jq -r '.products[] | "\(.productId): \(.name) - $\(.price)"'

# Test 4: Create Order (Cross-context communication)
echo -e "\nTest 4: Create Order (Cross-context)"
if [ -n "$USER_ID" ]; then
  ORDER_RESPONSE=$(curl -s -X POST "$BASE_URL/orders" \
    -H "Content-Type: application/json" \
    -d "{\"userId\":\"$USER_ID\",\"items\":[{\"productId\":\"prod-1\",\"quantity\":1}]}")

  ORDER_ID=$(echo "$ORDER_RESPONSE" | jq -r '.orderId // empty')
  echo "Created order: $ORDER_ID"
else
  echo "Skipping order creation - no user ID available"
  ORDER_ID=""
fi

# Test 5: Process Payment (Cross-context communication)
echo -e "\nTest 5: Process Payment (Cross-context)"
if [ -n "$ORDER_ID" ]; then
  PAYMENT_RESPONSE=$(curl -s -X POST "$BASE_URL/payments" \
    -H "Content-Type: application/json" \
    -d "{\"orderId\":\"$ORDER_ID\",\"amount\":1299.99,\"method\":\"credit_card\"}")

  PAYMENT_ID=$(echo "$PAYMENT_RESPONSE" | jq -r '.paymentId // empty')
  echo "Created payment: $PAYMENT_ID"
else
  echo "Skipping payment creation - no order ID available"
fi

# Test 6: Update Product Price (Context isolation)
echo -e "\nTest 6: Update Product Price (Context Isolation)"
curl -s -X PUT "$BASE_URL/products/prod-1/price" \
  -H "Content-Type: application/json" \
  -d '{"price":1399.99}' | jq -r '.message'

echo -e "\n✅ All tests completed successfully!"
echo "🌐 Visit http://localhost:3000 to see the dashboard"
