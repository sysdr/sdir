#!/bin/bash
set -euo pipefail
DEMO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$DEMO_ROOT"

BASE="${API_URL:-http://localhost:8000}"
echo "[test] Using API $BASE"

HEALTH=$(curl -sf "$BASE/health")
echo "$HEALTH" | python3 -c "import sys,json; d=json.load(sys.stdin); assert d['status']=='ok'" \
  && echo "[✓] Health OK" || { echo "[✗] Health failed"; exit 1; }

STATUS=$(curl -sf "$BASE/status")
echo "$STATUS" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'round' in d; assert 'status' in d" \
  && echo "[✓] Status OK" || { echo "[✗] Status failed"; exit 1; }

MODEL=$(curl -sf "$BASE/model")
echo "$MODEL" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'weights' in d; assert len(d['weights'])==3" \
  && echo "[✓] Model OK (3 weights)" || { echo "[✗] Model failed"; exit 1; }

METRICS=$(curl -sf "$BASE/metrics")
echo "$METRICS" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'metrics' in d" \
  && echo "[✓] Metrics OK" || { echo "[✗] Metrics failed"; exit 1; }

echo "[✓] All API tests passed."
