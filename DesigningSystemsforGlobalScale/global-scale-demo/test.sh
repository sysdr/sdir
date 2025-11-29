#!/bin/bash

echo "Running System Tests..."
echo "======================="

# Test 1: Health Check
echo -e "\n1. Testing Health Check..."
curl -s http://localhost:3000/api/health | grep -q "healthy" && echo "✓ Health check passed" || echo "✗ Health check failed"

# Test 2: Get All Listings
echo -e "\n2. Testing Listings Retrieval..."
LISTINGS=$(curl -s http://localhost:3000/api/listings/all)
COUNT=$(echo $LISTINGS | grep -o '"id"' | wc -l)
[ $COUNT -gt 0 ] && echo "✓ Retrieved $COUNT listings" || echo "✗ Failed to retrieve listings"

# Test 3: Single Booking
echo -e "\n3. Testing Single Booking..."
AVAILABLE_LISTING=$(echo "$LISTINGS" | python3 -c "import json,sys; data=json.load(sys.stdin); print(next((l['id'] for l in data.get('listings', []) if l.get('availability')=='available'), ''), end='')")

if [ -z "$AVAILABLE_LISTING" ]; then
  echo "✗ Booking failed (no available listings)"
else
  RESULT=$(curl -s -X POST http://localhost:3000/api/book \
    -H "Content-Type: application/json" \
    -d "{\"listingId\":\"$AVAILABLE_LISTING\",\"userId\":\"test-user-1\",\"userLocation\":\"new-york\"}")
  echo $RESULT | grep -q '"success":true' && echo "✓ Booking successful" || echo "✗ Booking failed"
fi

# Test 4: Concurrent Bookings (Conflict Test)
echo -e "\n4. Testing Concurrent Bookings..."
curl -s -X POST http://localhost:3000/api/book \
  -H "Content-Type: application/json" \
  -d '{"listingId":"eu-1","userId":"user-a","userLocation":"london"}' > /dev/null &
curl -s -X POST http://localhost:3000/api/book \
  -H "Content-Type: application/json" \
  -d '{"listingId":"eu-1","userId":"user-b","userLocation":"paris"}' > /dev/null &
wait
sleep 2
echo "✓ Conflict resolution test completed"

echo -e "\n======================="
echo "All tests completed!"
