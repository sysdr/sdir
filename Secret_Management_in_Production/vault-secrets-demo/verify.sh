#!/bin/bash
# Verify Vault Secrets Demo: files, services, and API/dashboard metrics.
# Run from vault-secrets-demo: ./verify.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="${VAULT_DEMO_DIR:-$SCRIPT_DIR}"

PASS=0
FAIL=0

# Usage: check "description" command [args...]
check() {
  local msg="$1"
  shift
  if "$@"; then
    echo "  ✅ $msg"
    ((PASS++)) || true
    return 0
  else
    echo "  ❌ $msg"
    ((FAIL++)) || true
    return 1
  fi
}

echo ""
echo "=== Verifying Vault Secrets Demo ==="
echo ""

# 1. Generated files
echo "[1] Generated files"
REQUIRED_FILES=(
  "$DEMO_DIR/docker-compose.yml"
  "$DEMO_DIR/backend/package.json"
  "$DEMO_DIR/backend/server.js"
  "$DEMO_DIR/backend/test.js"
  "$DEMO_DIR/backend/Dockerfile"
  "$DEMO_DIR/frontend/index.html"
  "$DEMO_DIR/scripts/demo.sh"
  "$DEMO_DIR/scripts/cleanup.sh"
)
MISSING=()
for f in "${REQUIRED_FILES[@]}"; do
  [[ -f "$f" ]] || MISSING+=("$f")
done
if [[ ${#MISSING[@]} -eq 0 ]]; then
  check "All ${#REQUIRED_FILES[@]} required files present" true
else
  check "Missing: ${MISSING[*]}" false
fi
echo ""

# 2. Docker / services (if Docker available)
echo "[2] Services"
if command -v docker &>/dev/null; then
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx vault-backend; then
    check "Container vault-backend running" true
  else
    check "Container vault-backend not running (run ./start.sh)" false
  fi
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx vault-demo; then
    check "Container vault-demo running" true
  else
    check "Container vault-demo not running" false
  fi
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx postgres-demo; then
    check "Container postgres-demo running" true
  else
    check "Container postgres-demo not running" false
  fi
else
  echo "  ⏭ Docker not available, skipping service checks"
fi
echo ""

# 3. API and metrics
echo "[3] API and dashboard metrics"
if command -v curl &>/dev/null; then
  STATUS=$(curl -sf http://localhost:3000/api/status 2>/dev/null) || true
  if [[ -n "$STATUS" ]]; then
    check "GET /api/status responds" true
    if echo "$STATUS" | grep -q '"ok":true'; then
      check "Backend status ok" true
    fi
    if echo "$STATUS" | grep -q '"initialized":true'; then
      check "Vault initialized" true
    fi
  else
    check "GET /api/status (backend not reachable at :3000?)" false
  fi

  SECRETS=$(curl -sf http://localhost:3000/api/secrets 2>/dev/null) || true
  if [[ -n "$SECRETS" ]]; then
    COUNT=$(echo "$SECRETS" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('secrets',[])))" 2>/dev/null) || echo "0"
    if [[ "$COUNT" -ge 3 ]]; then
      check "Secrets count >= 3 (got $COUNT)" true
    else
      check "Secrets count >= 3 (got $COUNT)" false
    fi
  fi

  AUDIT=$(curl -sf http://localhost:3000/api/audit 2>/dev/null) || true
  if [[ -n "$AUDIT" ]]; then
    EVENTS=$(echo "$AUDIT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('events',[])))" 2>/dev/null) || echo "0"
    if [[ "${EVENTS:-0}" -gt 0 ]]; then
      check "Audit events > 0 (got $EVENTS)" true
    else
      check "Audit endpoint responds" true
    fi
  fi

  WELLKNOWN=$(curl -sf -o /dev/null -w "%{http_code}" http://localhost:3000/.well-known/appspecific/com.chrome.devtools.json 2>/dev/null) || true
  if [[ "$WELLKNOWN" == "200" ]]; then
    check "Chrome DevTools well-known URL returns 200" true
  else
    check "Chrome DevTools well-known URL (got $WELLKNOWN)" false
  fi
else
  echo "  ⏭ curl not available, skipping API checks"
fi
echo ""

# Summary
echo "────────────────────────────────────────"
echo "Results: $PASS passed, $FAIL failed"
echo ""
if [[ $FAIL -gt 0 ]]; then
  echo "Run ./setup.sh then ./start.sh if services or files are missing."
  exit 1
fi
echo "✅ Verification passed."
exit 0
