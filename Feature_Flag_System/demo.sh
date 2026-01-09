#!/bin/bash

echo "=== Feature Flag System Demo ==="
echo ""

# Check if services are running
if [ ! -d "flag-system" ]; then
    echo "Error: flag-system directory not found."
    echo "Please run ./setup.sh first."
    exit 1
fi

cd flag-system

# Check if services are running
if ! docker-compose ps | grep -q "Up"; then
    echo "Services are not running. Starting services..."
    docker-compose up -d postgres redis flag-service checkout-service payment-service recommendations-service dashboard
    echo "Waiting for services to be ready..."
    sleep 5
fi

echo "Dashboard: http://localhost:8080"
echo "Flag Service API: http://localhost:3000"
echo ""

# Function to generate evaluations
generate_evaluations() {
    local flag_id=$1
    local count=$2
    local context=${3:-"{}"}
    for i in $(seq 1 $count); do
        curl -s -X POST http://localhost:3000/evaluate \
            -H 'Content-Type: application/json' \
            -d "{\"flagId\":\"$flag_id\",\"userId\":\"demo-user-$(date +%s)-$i\",\"context\":$context}" > /dev/null
    done
}

# Show current stats
echo "=== Current System Stats ==="
STATS=$(curl -s http://localhost:3000/stats)
echo "$STATS" | python3 -m json.tool 2>/dev/null || echo "$STATS"
echo ""

# Generate initial demo traffic
echo "=== Generating Demo Traffic ==="
echo "Generating evaluations for all flags..."
generate_evaluations "fast-checkout" 15 "{}"
generate_evaluations "new-payment-flow" 15 "{\"segment\":\"premium\",\"region\":\"US\"}"
generate_evaluations "recommendations-v2" 15 "{\"region\":\"US\"}"
generate_evaluations "dark-mode" 10 "{}"

sleep 2

# Show updated stats
echo ""
echo "=== Updated Stats After Demo Traffic ==="
STATS=$(curl -s http://localhost:3000/stats)
echo "$STATS" | python3 -m json.tool 2>/dev/null || echo "$STATS"
echo ""

# Show available flags
echo "=== Available Feature Flags ==="
FLAGS=$(curl -s http://localhost:3000/flags)
echo "$FLAGS" | python3 -m json.tool 2>/dev/null | grep -E '"id"|"name"|"enabled"|"rollout_percentage"' | head -20 || echo "$FLAGS" | head -20
echo ""

echo "=== Demo Commands ==="
echo ""
echo "1. View dashboard metrics:"
echo "   Open http://localhost:8080 in your browser"
echo ""
echo "2. Check current stats:"
echo "   curl http://localhost:3000/stats"
echo ""
echo "3. Evaluate a flag:"
echo "   curl -X POST http://localhost:3000/evaluate \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"flagId\":\"fast-checkout\",\"userId\":\"user-123\",\"context\":{}}'"
echo ""
echo "4. Toggle a flag:"
echo "   curl -X POST http://localhost:3000/flags/dark-mode/toggle"
echo ""
echo "5. Update rollout percentage:"
echo "   curl -X POST http://localhost:3000/flags/new-payment-flow/rollout \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"percentage\":75}'"
echo ""
echo "6. View service logs:"
echo "   cd flag-system && docker-compose logs -f"
echo ""
echo "7. Run continuous demo (generates traffic every 5 seconds):"
echo "   cd flag-system && ./run-demo.sh"
echo ""


