#!/bin/bash

echo "🔍 Validating Global Payment System..."
echo ""

# Check services are running
echo "1. Checking services..."
docker-compose ps | grep -E "Up|healthy" | wc -l | xargs -I {} echo "   Services running: {}"

# Check metrics endpoint
echo ""
echo "2. Checking metrics endpoint..."
METRICS=$(curl -s http://localhost:3000/api/metrics)
TOTAL=$(echo "$METRICS" | grep -o '"totalPayments":[0-9]*' | cut -d':' -f2)
SUCCESS=$(echo "$METRICS" | grep -o '"successfulPayments":[0-9]*' | cut -d':' -f2)
RATE=$(echo "$METRICS" | grep -o '"authorizationRate":"[^"]*"' | cut -d'"' -f4)

if [ -z "$TOTAL" ] || [ "$TOTAL" = "0" ]; then
  echo "   ❌ Total payments is zero or missing"
else
  echo "   ✅ Total payments: $TOTAL"
fi

if [ -z "$SUCCESS" ] || [ "$SUCCESS" = "0" ]; then
  echo "   ⚠️  Successful payments is zero (may be normal if no payments succeeded)"
else
  echo "   ✅ Successful payments: $SUCCESS"
fi

if [ -n "$RATE" ]; then
  echo "   ✅ Authorization rate: $RATE%"
else
  echo "   ❌ Authorization rate missing"
fi

# Check stats endpoint
echo ""
echo "3. Checking stats endpoint..."
STATS=$(curl -s http://localhost:3001/api/stats)
if echo "$STATS" | grep -q "byState"; then
  echo "   ✅ Stats endpoint working"
else
  echo "   ❌ Stats endpoint not working"
fi

# Check dashboard accessibility
echo ""
echo "4. Checking dashboard..."
if curl -s http://localhost:3002 | grep -q "Global Payment System"; then
  echo "   ✅ Dashboard accessible"
else
  echo "   ❌ Dashboard not accessible"
fi

# Check for duplicate services
echo ""
echo "5. Checking for duplicate services..."
DUPLICATES=$(docker ps --format "{{.Names}}" | grep -E "gateway|processor|dashboard" | sort | uniq -d)
if [ -z "$DUPLICATES" ]; then
  echo "   ✅ No duplicate services found"
else
  echo "   ⚠️  Duplicate services found: $DUPLICATES"
fi

echo ""
echo "✅ Validation complete!"

