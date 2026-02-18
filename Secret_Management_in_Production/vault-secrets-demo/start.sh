#!/bin/bash
# Start the Vault Secrets Demo services.
# Run from vault-secrets-demo: ./start.sh
# Requires setup.sh to have been run first (from parent directory).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="${VAULT_DEMO_DIR:-$SCRIPT_DIR}"

if [[ ! -f "$DEMO_DIR/docker-compose.yml" ]]; then
  echo "Error: vault-secrets-demo not found. Run ./setup.sh first."
  exit 1
fi

if ! command -v docker &>/dev/null; then
  echo "Error: Docker not found."
  exit 1
fi

if command -v docker-compose &>/dev/null; then
  COMPOSE_CMD="docker-compose"
elif docker compose version &>/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
else
  echo "Error: Docker Compose not found."
  exit 1
fi

echo "[start] Starting Vault demo services in $DEMO_DIR ..."
cd "$DEMO_DIR"
$COMPOSE_CMD up -d
echo "OK: Services started."
echo "  Dashboard  → http://localhost:3000"
echo "  Vault UI   → http://localhost:8200  (token: dev-root-token)"
echo "  PostgreSQL → localhost:5433"
