#!/bin/bash

echo "🧪 Running Federation Tests..."
echo "=============================="

# Check for JSON formatter
if command -v jq &> /dev/null; then
    FORMATTER="jq ."
elif command -v python3 &> /dev/null; then
    FORMATTER="python3 -m json.tool"
else
    FORMATTER="cat"
fi

sleep 5

echo -e "\n1️⃣ Test: Query Users Service"
response=$(curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ users { id name email } }"}')
echo "$response" | $FORMATTER
if echo "$response" | grep -q '"data"'; then
    echo "✅ Test 1 PASSED"
else
    echo "❌ Test 1 FAILED"
fi

echo -e "\n2️⃣ Test: Query Products with Reviews (Federation)"
response=$(curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ products { id name price reviews { rating comment } avgRating } }"}')
echo "$response" | $FORMATTER
if echo "$response" | grep -q '"data"'; then
    echo "✅ Test 2 PASSED"
else
    echo "❌ Test 2 FAILED"
fi

echo -e "\n3️⃣ Test: Query User with Reviews (Federation)"
response=$(curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ user(id: \"1\") { id name reviews { rating comment } } }"}')
echo "$response" | $FORMATTER
if echo "$response" | grep -q '"data"'; then
    echo "✅ Test 3 PASSED"
else
    echo "❌ Test 3 FAILED"
fi

echo -e "\n4️⃣ Test: Complex Federation Query"
response=$(curl -s -X POST http://localhost:4000/graphql \
  -H "Content-Type: application/json" \
  -d '{"query":"{ users { id name reviews { rating } } products { id name avgRating reviewCount } }"}')
echo "$response" | $FORMATTER
if echo "$response" | grep -q '"data"'; then
    echo "✅ Test 4 PASSED"
else
    echo "❌ Test 4 FAILED"
fi

echo -e "\n✅ All tests completed!"
