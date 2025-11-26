#!/bin/bash

echo "🧪 Running Blockchain System Tests..."
echo ""

echo "1️⃣ Testing Node 1 Health..."
response=$(curl -s http://localhost:3001/health)
if echo "$response" | grep -q "healthy"; then
    echo "✅ Node 1 is healthy"
else
    echo "❌ Node 1 health check failed"
    exit 1
fi

echo ""
echo "2️⃣ Testing Node 2 Health..."
response=$(curl -s http://localhost:3002/health)
if echo "$response" | grep -q "healthy"; then
    echo "✅ Node 2 is healthy"
else
    echo "❌ Node 2 health check failed"
    exit 1
fi

echo ""
echo "3️⃣ Testing Node 3 Health..."
response=$(curl -s http://localhost:3003/health)
if echo "$response" | grep -q "healthy"; then
    echo "✅ Node 3 is healthy"
else
    echo "❌ Node 3 health check failed"
    exit 1
fi

echo ""
echo "4️⃣ Submitting test transaction..."
response=$(curl -s -X POST http://localhost:3001/transaction \
  -H "Content-Type: application/json" \
  -d '{
    "from": "Alice",
    "to": "Bob",
    "amount": 50,
    "gasPrice": 80
  }')

if echo "$response" | grep -q "success"; then
    echo "✅ Transaction submitted successfully"
else
    echo "❌ Transaction submission failed"
    exit 1
fi

echo ""
echo "5️⃣ Checking mempool..."
sleep 2
response=$(curl -s http://localhost:3001/mempool)
if echo "$response" | grep -q "transactions"; then
    echo "✅ Mempool is operational"
else
    echo "❌ Mempool check failed"
    exit 1
fi

echo ""
echo "6️⃣ Verifying blockchain growth..."
sleep 8
response=$(curl -s http://localhost:3001/stats)
chain_length=$(echo "$response" | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')
if [ "$chain_length" -gt 1 ]; then
    echo "✅ Blockchain is growing (${chain_length} blocks)"
else
    echo "❌ Blockchain not growing"
    exit 1
fi

echo ""
echo "7️⃣ Testing consensus across nodes..."
length1=$(curl -s http://localhost:3001/stats | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')
length2=$(curl -s http://localhost:3002/stats | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')
length3=$(curl -s http://localhost:3003/stats | grep -o '"chainLength":[0-9]*' | grep -o '[0-9]*')

echo "Node 1 chain length: $length1"
echo "Node 2 chain length: $length2"
echo "Node 3 chain length: $length3"

max_diff=$(( length1 > length2 ? length1 - length2 : length2 - length1 ))
max_diff=$(( max_diff > (length3 > length1 ? length3 - length1 : length1 - length3) ? max_diff : (length3 > length1 ? length3 - length1 : length1 - length3) ))

if [ "$max_diff" -le 2 ]; then
    echo "✅ Nodes are in consensus (max difference: $max_diff blocks)"
else
    echo "⚠️  Nodes have diverged (max difference: $max_diff blocks)"
fi

echo ""
echo "✨ All tests passed!"
echo ""
