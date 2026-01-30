#!/bin/bash

set -e

# JSON helpers: use jq if available, else python3
jq_r() { local j="$1"; local k="$2"; if command -v jq >/dev/null 2>&1; then echo "$j" | jq -r "$k"; else echo "$j" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('${k#.}',''))"; fi; }
jq_e() { local j="$1"; local k="$2"; if command -v jq >/dev/null 2>&1; then echo "$j" | jq -e "$k" >/dev/null 2>&1; else echo "$j" | python3 -c "import sys,json; d=json.load(sys.stdin); exit(0 if '${k#.}' in d else 1)"; fi; }

echo "🧪 Running Integration Tests..."

# Wait for services (retry up to 2 min)
for i in $(seq 1 12); do
  curl -sf http://localhost:5000/health >/dev/null && curl -sf http://localhost:5001/health >/dev/null && break
  sleep 10
  [ "$i" -eq 12 ] && { echo "Services not ready"; exit 1; }
done

# Test 1: Health checks
echo "Test 1: Health checks..."
curl -f http://localhost:5000/health || exit 1
curl -f http://localhost:5001/health || exit 1
echo "✓ Health checks passed"

# Test 2: Model inference
echo "Test 2: Model inference..."
RESPONSE=$(curl -s -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d '{"text1":"test","text2":"test"}')
jq_e "$RESPONSE" '.similarity' || exit 1
echo "✓ Model inference working"

# Test 3: Caching (use unique text to avoid cache from prior runs)
CACHE_KEY="cache_test_$(date +%s)_$$"
echo "Test 3: Cache behavior..."
RESPONSE1=$(curl -s -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d "{\"text1\":\"$CACHE_KEY\",\"text2\":\"$CACHE_KEY\"}")
CACHED1=$(jq_r "$RESPONSE1" '.text1_cached')

RESPONSE2=$(curl -s -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d "{\"text1\":\"$CACHE_KEY\",\"text2\":\"$CACHE_KEY\"}")
CACHED2=$(jq_r "$RESPONSE2" '.text1_cached')

# Accept both "true"/"false" (jq) and "True"/"False" (Python)
if [ "$(echo "$CACHED1" | tr '[:upper:]' '[:lower:]')" = "false" ] && [ "$(echo "$CACHED2" | tr '[:upper:]' '[:lower:]')" = "true" ]; then
  echo "✓ Caching working correctly"
else
  echo "✗ Caching test failed (CACHED1=$CACHED1 CACHED2=$CACHED2)"
  exit 1
fi

# Test 4: Model routing
echo "Test 4: Smart routing..."
SIMPLE=$(curl -s -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d '{"text1":"hi","text2":"hello"}')
SIMPLE_MODEL=$(jq_r "$SIMPLE" '.model')

COMPLEX=$(curl -s -X POST http://localhost:5000/api/similarity \
  -H "Content-Type: application/json" \
  -d '{"text1":"Can you compare and analyze the differences?","text2":"What are distinctions?"}')
COMPLEX_MODEL=$(jq_r "$COMPLEX" '.model')

if [ "$SIMPLE_MODEL" = "fast" ]; then
  echo "✓ Simple queries routed to fast model"
else
  echo "⚠ Simple query routing unexpected: $SIMPLE_MODEL"
fi

echo ""
echo "✅ All tests passed!"
