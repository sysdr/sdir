#!/bin/bash

echo "🧪 Running Cache Stampede Tests..."

BASE_URL="http://localhost:3001"

# Reset metrics
curl -s -X POST "$BASE_URL/api/reset" > /dev/null

echo ""
echo "Test 1: No Mitigation (Should cause stampede)"
echo "Sending 50 concurrent requests..."

# Send concurrent requests
for i in {1..50}; do
  curl -s "$BASE_URL/api/product/1/no-mitigation" > /dev/null &
done
wait

sleep 1
METRICS=$(curl -s "$BASE_URL/api/metrics")
DB_QUERIES=$(echo $METRICS | grep -o '"dbQueries":[0-9]*' | grep -o '[0-9]*')

echo "DB Queries: $DB_QUERIES"
if [ "$DB_QUERIES" -gt 40 ]; then
  echo "✅ PASS: Stampede occurred ($DB_QUERIES queries for 50 requests)"
else
  echo "❌ FAIL: Expected >40 queries, got $DB_QUERIES"
fi

echo ""
echo "Test 2: Request Coalescing (Should prevent stampede)"
curl -s -X POST "$BASE_URL/api/reset" > /dev/null

for i in {1..50}; do
  curl -s "$BASE_URL/api/product/1/coalescing" > /dev/null &
done
wait

sleep 1
METRICS=$(curl -s "$BASE_URL/api/metrics")
DB_QUERIES=$(echo $METRICS | grep -o '"dbQueries":[0-9]*' | grep -o '[0-9]*')
COALESCED=$(echo $METRICS | grep -o '"coalesced":[0-9]*' | grep -o '[0-9]*')

echo "DB Queries: $DB_QUERIES, Coalesced: $COALESCED"
if [ "$DB_QUERIES" -lt 5 ] && [ "$COALESCED" -gt 40 ]; then
  echo "✅ PASS: Coalescing prevented stampede ($COALESCED requests coalesced)"
else
  echo "❌ FAIL: Expected <5 queries and >40 coalesced"
fi

echo ""
echo "Test 3: Stale-While-Revalidate"
curl -s -X POST "$BASE_URL/api/reset" > /dev/null

# Prime cache
curl -s "$BASE_URL/api/product/1/stale-revalidate" > /dev/null
sleep 6  # Wait for cache to expire

# This should serve stale data
RESPONSE=$(curl -s "$BASE_URL/api/product/1/stale-revalidate")
IS_STALE=$(echo $RESPONSE | grep -o '"stale":true')

if [ ! -z "$IS_STALE" ]; then
  echo "✅ PASS: Served stale data while revalidating"
else
  echo "❌ FAIL: Did not serve stale data"
fi

echo ""
echo "All tests completed!"
