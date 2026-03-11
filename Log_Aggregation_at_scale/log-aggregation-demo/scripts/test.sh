#!/bin/bash
BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE" || exit 1
PASS=0 FAIL=0
check() { local d="$1"; shift; if eval "$@" >/dev/null 2>&1; then echo "  PASS: $d"; PASS=$((PASS+1)); else echo "  FAIL: $d"; FAIL=$((FAIL+1)); fi; }
echo "Running tests from $BASE"
echo ""
check "Loki API" "curl -s http://localhost:3100/ready | grep -q ready"
check "Elasticsearch health" "curl -s http://localhost:9200/_cluster/health | grep -qE '\''\"status\":\"(green|yellow)\"'"
check "Grafana API" "curl -s http://localhost:3001/api/health | grep -q ok"
check "Frontend HTTP 200" "curl -s -o /dev/null -w '%{http_code}' http://localhost:8214 | grep -q 200"
LOG_FILES=$(docker-compose exec -T load-generator sh -c 'ls /var/log/app/*.log 2>/dev/null' | wc -l)
if [ "${LOG_FILES:-0}" -gt 0 ]; then echo "  PASS: Log files generated ($LOG_FILES files)"; PASS=$((PASS+1)); else echo "  FAIL: Log files"; FAIL=$((FAIL+1)); fi
DASH=$(curl -s http://localhost:8214)
echo "$DASH" | grep -q 'id="logs-ingested"' && echo "  PASS: Dashboard has logs-ingested metric" && PASS=$((PASS+1)) || { echo "  FAIL: Dashboard metric logs-ingested"; FAIL=$((FAIL+1)); }
echo "$DASH" | grep -q 'setInterval(generateLog' && echo "  PASS: Dashboard metrics auto-update (generateLog)" && PASS=$((PASS+1)) || { echo "  FAIL: Dashboard update script"; FAIL=$((FAIL+1)); }
echo ""
echo "Result: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
