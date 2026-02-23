#!/bin/bash
set -e
DEMO_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DEMO_DIR"
echo "🧪 Little's Law Demo — Validation Tests"
echo ""

# Ensure services are up
if ! curl -sf http://localhost:3001/health >/dev/null 2>&1; then
  echo "❌ API Gateway not responding. Start with: docker compose up -d"
  exit 1
fi

PASS=0
FAIL=0

# 1. Gateway health
if curl -sf http://localhost:3001/health | grep -q '"status":"ok"'; then
  echo "  ✅ Gateway health"
  PASS=$((PASS+1))
else
  echo "  ❌ Gateway health"
  FAIL=$((FAIL+1))
fi

# 2. Request pipeline (L field)
if curl -sf http://localhost:3001/api/process | grep -q '"current_L"'; then
  echo "  ✅ Request pipeline (L field present)"
  PASS=$((PASS+1))
else
  echo "  ❌ Request pipeline"
  FAIL=$((FAIL+1))
fi

# 3. Little's Law stats endpoint
if curl -sf http://localhost:3001/api/littles-law-stats | grep -q '"formula"'; then
  echo "  ✅ Little's Law stats endpoint"
  PASS=$((PASS+1))
else
  echo "  ❌ Stats endpoint"
  FAIL=$((FAIL+1))
fi

# 4. App server (for dashboard Predicted L / latency control)
if curl -sf http://localhost:3002/api/current-state >/dev/null 2>&1; then
  echo "  ✅ App server current-state"
  PASS=$((PASS+1))
else
  echo "  ❌ App server (port 3002)"
  FAIL=$((FAIL+1))
fi

# 5. Dashboard
if curl -sf http://localhost:8080/ | grep -qE 'html|DOCTYPE'; then
  echo "  ✅ Dashboard serving"
  PASS=$((PASS+1))
else
  echo "  ❌ Dashboard (port 8080)"
  FAIL=$((FAIL+1))
fi

echo ""
echo "Result: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] && exit 0 || exit 1
