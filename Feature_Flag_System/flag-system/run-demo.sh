#!/bin/bash

echo "=== Feature Flag System Demo ==="
echo ""
echo "Dashboard: http://localhost:8080"
echo "Flag Service API: http://localhost:3000"
echo ""
echo "Generating evaluation traffic to update dashboard metrics..."
echo "Press Ctrl+C to stop"
echo ""

# Function to generate evaluations
generate_evaluations() {
  local flag_id=$1
  local count=$2
  for i in $(seq 1 $count); do
    curl -s -X POST http://localhost:3000/evaluate \
      -H 'Content-Type: application/json' \
      -d "{\"flagId\":\"$flag_id\",\"userId\":\"demo-user-$(date +%s)-$i\",\"context\":{}}" > /dev/null
  done
}

# Generate initial batch
echo "Generating initial evaluation batch..."
generate_evaluations "fast-checkout" 10
generate_evaluations "new-payment-flow" 10
generate_evaluations "recommendations-v2" 10

# Show current stats
echo ""
echo "Current Stats:"
curl -s http://localhost:3000/stats | python3 -m json.tool 2>/dev/null || curl -s http://localhost:3000/stats
echo ""

# Continuously generate evaluations
while true; do
  sleep 5
  generate_evaluations "fast-checkout" 5
  generate_evaluations "new-payment-flow" 5
  generate_evaluations "recommendations-v2" 3
  echo "$(date): Generated evaluations"
done


