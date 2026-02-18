#!/bin/bash
BASE="http://localhost:3000"
PASS=0; FAIL=0

chk() {
  local label="$1"; local cmd="$2"; local expect="$3"
  local actual; actual=$(eval "$cmd" 2>/dev/null)
  if echo "$actual" | grep -q "$expect"; then
    echo "  ✓ $label"; ((PASS++))
  else
    echo "  ✗ $label (got: $actual)"; ((FAIL++))
  fi
}

echo ""
echo "Running integration tests..."
echo ""

chk "Health endpoint returns ok"        "curl -sf $BASE/health"              '"ok"'
chk "Stats endpoint reachable"          "curl -sf $BASE/stats"               '"received"'
chk "Strategy: head_probabilistic"      "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"head_probabilistic\"}'" '"ok":true'
chk "Strategy: head_rate_limited"       "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"head_rate_limited\"}'"  '"ok":true'
chk "Strategy: tail_based"             "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"tail_based\"}'"          '"ok":true'
chk "Strategy: adaptive"               "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"adaptive\"}'"            '"ok":true'
chk "Reject unknown strategy"          "curl -sf -X POST $BASE/strategy -H 'Content-Type: application/json' -d '{\"strategy\":\"unknown\"}'|| echo 'error'"  'error'
chk "Trace ingestion endpoint"         "curl -sf -X POST $BASE/trace -H 'Content-Type: application/json' -d '{\"traceId\":\"test123\",\"type\":\"normal\",\"totalDuration\":120,\"spanCount\":3,\"hasError\":false,\"spans\":[]}'" '"sampled"'
chk "Trace feed populated in stats"    "curl -sf $BASE/stats"               '"recentTraces"'

echo ""
echo "Results: ${PASS} passed, ${FAIL} failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
