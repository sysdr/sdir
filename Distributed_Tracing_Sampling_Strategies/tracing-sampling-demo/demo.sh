#!/bin/bash
echo "Switching strategies every 15 seconds for live comparison..."
echo ""
STRATEGIES=("tail_based" "head_probabilistic" "adaptive" "head_rate_limited")
for S in "${STRATEGIES[@]}"; do
  echo "→ Setting strategy: $S"
  curl -sf -X POST http://localhost:3000/strategy \
    -H 'Content-Type: application/json' \
    -d "{\"strategy\":\"$S\"}" | python3 -m json.tool 2>/dev/null || true
  echo "   (watching for 15 seconds — check http://localhost:3000)"
  sleep 15
done
echo ""
echo "Demo complete. Open http://localhost:3000 to explore."
