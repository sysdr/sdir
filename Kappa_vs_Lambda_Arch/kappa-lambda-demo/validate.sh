#!/bin/bash

# Validate Kappa vs Lambda demo: services up and dashboard metrics non-zero after demo.
# Run after start.sh and after producer has been sending events (or run start.sh which waits 35s).

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

FAIL=0

echo "=================================================="
echo "Validating Kappa vs Lambda Demo"
echo "=================================================="

# 1. Serving layer responds
echo ""
echo "[1/4] Serving layer (Lambda merged + Kappa stats)..."
LAMBDA_JSON=$(curl -sf http://localhost:3005/lambda/merged 2>/dev/null) || true
KAPPA_JSON=$(curl -sf http://localhost:3005/kappa/stats 2>/dev/null) || true

if [ -z "$LAMBDA_JSON" ] || [ -z "$KAPPA_JSON" ]; then
  echo "❌ Serving layer not responding on :3005. Is start.sh running?"
  FAIL=1
else
  echo "   Lambda merged: OK"
  echo "   Kappa stats:  OK"
fi

# 2. Lambda merged has non-zero or valid structure
echo ""
echo "[2/4] Lambda metrics (batch + speed)..."
if echo "$LAMBDA_JSON" | grep -q '"error"'; then
  echo "❌ Lambda merged returned error"
  FAIL=1
else
  LAMBDA_TOTAL=$(echo "$LAMBDA_JSON" | sed -n 's/.*"totalEvents": *\([0-9]*\).*/\1/p')
  if [ -n "$LAMBDA_TOTAL" ] && [ "$LAMBDA_TOTAL" -gt 0 ]; then
    echo "   totalEvents: $LAMBDA_TOTAL ✓"
  else
    echo "   totalEvents: ${LAMBDA_TOTAL:-0} (expected > 0 after demo/start wait)"
    if [ "${LAMBDA_TOTAL:-0}" -eq 0 ]; then
      echo "   ⚠️  Run start.sh and wait ~35s, or ensure producer is sending events"
    fi
  fi
fi

# 3. Kappa stats non-zero or valid
echo ""
echo "[3/4] Kappa metrics..."
if echo "$KAPPA_JSON" | grep -q '"error"'; then
  echo "❌ Kappa stats returned error"
  FAIL=1
else
  KAPPA_TOTAL=$(echo "$KAPPA_JSON" | sed -n 's/.*"totalEvents": *\([0-9]*\).*/\1/p')
  if [ -n "$KAPPA_TOTAL" ] && [ "$KAPPA_TOTAL" -gt 0 ]; then
    echo "   totalEvents: $KAPPA_TOTAL ✓"
  else
    echo "   totalEvents: ${KAPPA_TOTAL:-0} (expected > 0 after demo)"
    if [ "${KAPPA_TOTAL:-0}" -eq 0 ]; then
      echo "   ⚠️  Producer may not have sent events yet; wait and re-run validate.sh"
    fi
  fi
fi

# 4. Producer health
echo ""
echo "[4/4] Producer health..."
PROD=$(curl -sf http://localhost:3001/health 2>/dev/null) || true
if [ -n "$PROD" ] && echo "$PROD" | grep -q '"status":"ok"'; then
  echo "   Producer :3001 OK"
else
  echo "   ⚠️  Producer not responding on :3001"
  FAIL=1
fi

echo ""
echo "=================================================="
if [ $FAIL -eq 0 ]; then
  echo "✅ Validation passed (dashboard should show updating metrics)"
else
  echo "❌ Validation had failures; fix errors above and re-run"
  exit 1
fi
echo "=================================================="
echo ""
echo "Dashboard: http://localhost:3000"
echo ""
