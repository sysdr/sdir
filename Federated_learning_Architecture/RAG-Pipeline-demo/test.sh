#!/bin/bash
set -e
BASE="${1:-http://localhost:8000}"
echo "Waiting for backend at $BASE ..."
for i in $(seq 1 90); do
  if curl -sf "$BASE/health" 2>/dev/null | grep -q '"status":"ready"'; then
    echo "Backend ready."
    break
  fi
  if [ "$i" -eq 90 ]; then echo "Timeout waiting for ready status"; exit 1; fi
  sleep 2
done
curl -sf "$BASE/health" | grep -q '"status":"ready"'
OUT=$(curl -sf -X POST "$BASE/search" -H "Content-Type: application/json" \
  -d '{"query":"consistent hashing virtual nodes","top_k":3}')
echo "$OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); r=d.get('results',[]); assert len(r)>=1, r; assert all(float(x.get('score',-1))>=0 for x in r); assert float(d.get('latency_ms',-1))>=0"
echo "All tests passed."
