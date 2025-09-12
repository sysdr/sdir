#!/bin/bash
echo "🧪 Running distributed debugging tests..."

# Wait for services to be ready
sleep 10

# Test health endpoints
echo "Testing service health..."
for port in 3001 3002 3003 3004; do
  if curl -s http://localhost:$port/health > /dev/null; then
    echo "✅ Service on port $port is healthy"
  else
    echo "❌ Service on port $port is unhealthy"
  fi
done

# Test dashboard
echo "Testing dashboard..."
if curl -s http://localhost:8080/api/health > /dev/null; then
  echo "✅ Dashboard is accessible"
else
  echo "❌ Dashboard is not accessible"
fi

# Create a test order
echo "Creating test order for debugging..."
RESPONSE=$(curl -s -X POST http://localhost:3001/orders \
  -H "Content-Type: application/json" \
  -d '{
    "userId": "test-user",
    "items": [{"id": "item1", "quantity": 1}],
    "total": 29.99
  }')

if echo "$RESPONSE" | grep -q "correlationId"; then
  echo "✅ Test order created successfully"
  CORRELATION_ID=$(echo "$RESPONSE" | grep -o '"correlationId":"[^"]*"' | cut -d'"' -f4)
  echo "📋 Correlation ID: $CORRELATION_ID"
else
  echo "❌ Failed to create test order"
  echo "Response: $RESPONSE"
fi

echo ""
echo "🎉 Tests completed!"
echo "🌐 Open http://localhost:8080 to view the debugging dashboard"
