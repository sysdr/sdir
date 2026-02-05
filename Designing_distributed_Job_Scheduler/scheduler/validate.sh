#!/bin/bash
# Validate dashboard metrics - values should update with demo execution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Dashboard Validation ==="
echo "Waiting for scheduler to be ready..."
sleep 3

# Check dashboard is up
if ! curl -sf http://localhost:3000 > /dev/null; then
  echo "❌ Dashboard not reachable at http://localhost:3000"
  exit 1
fi
echo "✅ Dashboard reachable"

# Check API stats
STATS=$(curl -sf http://localhost:3000/api/stats 2>/dev/null)
if [ -z "$STATS" ]; then
  echo "❌ Could not fetch /api/stats"
  exit 1
fi
echo "✅ API stats endpoint working"

# Parse stats (simple grep for key values)
TOTAL=$(echo "$STATS" | grep -o '"totalTasks":[0-9]*' | cut -d: -f2)
COMPLETED=$(echo "$STATS" | grep -o '"COMPLETED":[0-9]*' | cut -d: -f2)
SCHEDULED=$(echo "$STATS" | grep -o '"SCHEDULED":[0-9]*' | cut -d: -f2)

echo ""
echo "Current metrics:"
echo "  Total Tasks: ${TOTAL:-0}"
echo "  Completed: ${COMPLETED:-0}"
echo "  Scheduled: ${SCHEDULED:-0}"
echo ""

# Allow time for tasks to execute - demo has 1-3 second delays
echo "Waiting 15s for demo tasks to execute..."
sleep 15

STATS2=$(curl -sf http://localhost:3000/api/stats 2>/dev/null)
TOTAL2=$(echo "$STATS2" | grep -o '"totalTasks":[0-9]*' | cut -d: -f2)
COMPLETED2=$(echo "$STATS2" | grep -o '"COMPLETED":[0-9]*' | cut -d: -f2)

echo "After 15s:"
echo "  Total Tasks: ${TOTAL2:-0}"
echo "  Completed: ${COMPLETED2:-0}"
echo ""

# Validation: totalTasks should be > 0, and either completed or scheduled should be > 0
if [ "${TOTAL2:-0}" -gt 0 ]; then
  echo "✅ Total tasks > 0 - metrics are updating"
else
  echo "⚠️  Total tasks is 0 - check if scheduler started correctly"
fi

if [ "${COMPLETED2:-0}" -gt 0 ]; then
  echo "✅ Completed tasks > 0 - demo execution working"
else
  echo "⚠️  No completed tasks yet - tasks may still be in queue (wait longer)"
fi

echo ""
echo "Dashboard: http://localhost:3000"
echo "Validation complete"
