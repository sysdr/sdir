#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
if [ ! -d "thundering-herd" ]; then
    echo "⚠️  thundering-herd not found. Run ./setup.sh or ./build.sh first."
    exit 1
fi
echo "🎯 Cache Stampede Mitigation Demo"
echo ""
echo "Dashboard: http://localhost:3000"
echo "Backend API: http://localhost:3001"
echo ""
echo "Try these strategies:"
echo "1. No Mitigation - Watch DB connections spike to 100+"
echo "2. Request Coalescing - Reduces to 1-2 queries"
echo "3. Probabilistic Early Expiration - Spreads load over time"
echo "4. Stale-While-Revalidate - Zero user-facing latency"
echo "5. Jittered TTL - Prevents synchronized expiration"
echo ""
echo "Running automated tests..."
bash "$SCRIPT_DIR/thundering-herd/tests/test-stampede.sh"
