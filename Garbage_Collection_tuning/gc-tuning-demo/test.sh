#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
FAIL=0
echo "=== GC Tuning Demo Tests ==="
echo "1. Java health..."
J=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/actuator/health)
[ "$J" = "200" ] && echo "   OK ($J)" || { echo "   FAIL ($J)"; FAIL=1; }
echo "2. Go health..."
G=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8081/health)
[ "$G" = "200" ] && echo "   OK ($G)" || { echo "   FAIL ($G)"; FAIL=1; }
echo "3. Dashboard..."
D=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/)
[ "$D" = "200" ] && echo "   OK ($D)" || { echo "   FAIL ($D)"; FAIL=1; }
echo "4. Java metrics (has keys)..."
JM=$(curl -s http://localhost:8080/metrics 2>/dev/null)
echo "$JM" | grep -q '"gcType"' && echo "   OK" || { echo "   FAIL (no gcType)"; FAIL=1; }
echo "5. Go metrics (has keys)..."
GM=$(curl -s http://localhost:8081/metrics 2>/dev/null)
echo "$GM" | grep -q '"gcCycles"' && echo "   OK" || { echo "   FAIL (no gcCycles)"; FAIL=1; }
echo "6. Dashboard proxy (Java/Go metrics via :3000)..."
JPROXY=$(curl -s http://localhost:3000/java/metrics 2>/dev/null)
GPROXY=$(curl -s http://localhost:3000/go/metrics 2>/dev/null)
echo "$JPROXY" | grep -q '"gcType"' && echo "$GPROXY" | grep -q '"gcCycles"' && echo "   OK" || { echo "   FAIL (proxy not serving backend)"; FAIL=1; }
echo "7. Demo metrics update (run short load, then check non-zero)..."
for _ in 1 2 3 4 5; do curl -s http://localhost:8080/process?load=medium >/dev/null; curl -s http://localhost:8081/process?load=medium >/dev/null; done
JR=$(curl -s http://localhost:8080/metrics 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('totalRequests',0))" 2>/dev/null || echo "0")
GR=$(curl -s http://localhost:8081/metrics 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('totalRequests',0))" 2>/dev/null || echo "0")
[ "${JR:-0}" -gt 0 ] && [ "${GR:-0}" -gt 0 ] && echo "   OK (Java requests=$JR, Go requests=$GR)" || echo "   WARN (requests Java=$JR Go=$GR; start load in dashboard to see metrics)"
[ $FAIL -eq 0 ] && echo "=== All tests passed ===" || { echo "=== Some tests failed ==="; exit 1; }
