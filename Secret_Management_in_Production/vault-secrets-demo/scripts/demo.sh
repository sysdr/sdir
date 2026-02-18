#!/bin/bash
# Interactive demo scenarios for the Vault dashboard

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "\n${BLUE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Vault Secret Management — Demo Scenarios      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}\n"

BASE="http://localhost:3000"

echo -e "${YELLOW}[Scenario 1] List KV secrets${NC}"
curl -s "$BASE/api/secrets" | python3 -m json.tool 2>/dev/null || curl -s "$BASE/api/secrets"

echo -e "\n${YELLOW}[Scenario 2] Issue a dynamic DB credential (app-role, TTL=120s)${NC}"
CRED=$(curl -s -X POST "$BASE/api/creds/dynamic" -H "Content-Type: application/json" -d '{"role":"app-role"}')
echo "$CRED" | python3 -m json.tool 2>/dev/null || echo "$CRED"

USERNAME=$(echo "$CRED" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('username',''))" 2>/dev/null)
PASSWORD=$(echo "$CRED" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('password',''))" 2>/dev/null)
LEASE_ID=$(echo "$CRED" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('id',''))" 2>/dev/null)

if [ -n "$USERNAME" ]; then
  echo -e "\n${GREEN}✅ Credential issued: $USERNAME${NC}"
  echo -e "${YELLOW}[Scenario 3] Verify credential against PostgreSQL${NC}"
  curl -s -X POST "$BASE/api/verify-cred" -H "Content-Type: application/json" \
    -d "{\"username\":\"$USERNAME\",\"password\":\"$PASSWORD\"}" | python3 -m json.tool 2>/dev/null
fi

echo -e "\n${YELLOW}[Scenario 4] Rotate a KV secret value${NC}"
curl -s -X POST "$BASE/api/rotate" -H "Content-Type: application/json" \
  -d '{"path":"app/stripe","key":"api_key"}' | python3 -m json.tool 2>/dev/null

if [ -n "$LEASE_ID" ]; then
  echo -e "\n${YELLOW}[Scenario 5] Explicitly revoke the dynamic credential${NC}"
  curl -s -X DELETE "$BASE/api/creds/$LEASE_ID" | python3 -m json.tool 2>/dev/null
fi

echo -e "\n${GREEN}✅ Demo complete. Open http://localhost:3000 to see the live dashboard.${NC}"
