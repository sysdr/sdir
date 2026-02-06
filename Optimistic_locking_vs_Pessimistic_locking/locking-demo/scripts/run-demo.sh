#!/bin/bash

API_URL="${API_URL:-http://localhost:3001}"
echo "🎯 Triggering demo transactions via API..."
echo ""

# Reset first
echo "Resetting account..."
curl -s -X POST "${API_URL}/api/reset" -H "Content-Type: application/json" | head -1
echo ""

# Run pessimistic batch
echo "Running 20 Pessimistic transactions..."
curl -s -X POST "${API_URL}/api/batch" -H "Content-Type: application/json" \
  -d '{"mode":"pessimistic","count":20,"amount":10}' | head -1
echo ""

sleep 2

# Run optimistic batch
echo "Running 20 Optimistic transactions..."
curl -s -X POST "${API_URL}/api/batch" -H "Content-Type: application/json" \
  -d '{"mode":"optimistic","count":20,"amount":-5}' | head -1
echo ""

echo "✅ Demo transactions complete! Check dashboard at http://localhost:3000"
