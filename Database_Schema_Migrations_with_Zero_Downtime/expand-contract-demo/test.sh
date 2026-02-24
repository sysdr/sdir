#!/bin/bash
# Smoke tests for Expand-Contract demo. Run after setup.sh (demo must be up).
# Usage: bash test.sh   or from demo dir: bash /path/to/test.sh
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/expand-contract-demo/setup.sh" ]; then
  DEMO_DIR="$SCRIPT_DIR"
else
  DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi
API="${API:-http://localhost:3001}"
FAIL=0

echo "▶  Testing API at $API ..."

if ! curl -sf "$API/health" > /dev/null; then
  echo "  ❌ Backend not reachable at $API. Start demo first: bash $DEMO_DIR/start.sh"
  exit 1
fi
echo "  ✅ Health OK"

STATE=$(curl -sf "$API/api/state" || true)
if echo "$STATE" | grep -q "current_phase"; then
  echo "  ✅ /api/state OK"
else
  echo "  ❌ /api/state failed"; FAIL=1
fi

if echo "$STATE" | grep -q '"full_name":[0-9]*'; then
  ROW=$(echo "$STATE" | grep -o '"full_name":[0-9]*' | head -1 | grep -o '[0-9]*')
  echo "  ✅ Column counts present (full_name: $ROW) — dashboard will show non-zero"
  if [ -n "$ROW" ] && [ "$ROW" -lt "1" ]; then
    echo "  ❌ full_name count should be > 0 for dashboard"; FAIL=1
  fi
else
  echo "  ❌ colCounts.full_name missing or zero"; FAIL=1
fi

# Dashboard expects these keys in /api/state
for key in state columns migrations lockEvents colCounts sampleRows; do
  if echo "$STATE" | grep -q "\"$key\""; then
    : # OK
  else
    echo "  ❌ /api/state missing key: $key"; FAIL=1
  fi
done
if [ "$FAIL" -eq 0 ]; then
  echo "  ✅ Dashboard API shape OK (state, columns, migrations, lockEvents, colCounts, sampleRows)"
fi

EXP=$(curl -sf -X POST "$API/api/migrate/expand" -H 'Content-Type: application/json' || true)
if echo "$EXP" | grep -q '"success":true'; then
  echo "  ✅ Expand phase OK"
else
  echo "  ❌ Expand failed"; FAIL=1
fi

WRT=$(curl -sf -X POST "$API/api/simulate/write" -H 'Content-Type: application/json' || true)
if echo "$WRT" | grep -q '"success":true'; then
  echo "  ✅ Simulate write OK"
else
  echo "  ❌ Simulate write failed"; FAIL=1
fi

if [ "$FAIL" -eq 0 ]; then
  echo ""
  echo "  ✅ All tests passed. Dashboard metrics should be non-zero at http://localhost:3000"
  exit 0
else
  echo ""
  echo "  ⚠️  Some tests failed"
  exit 1
fi
