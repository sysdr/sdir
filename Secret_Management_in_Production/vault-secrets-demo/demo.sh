#!/bin/bash
# Run Vault demo scenarios (list secrets, issue dynamic creds, verify, rotate, revoke).
# Run from vault-secrets-demo: ./demo.sh
# Requires setup.sh to have been run and services started (./start.sh).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="${VAULT_DEMO_DIR:-$SCRIPT_DIR}"
DEMO_SCRIPT="$DEMO_DIR/scripts/demo.sh"

if [[ ! -x "$DEMO_SCRIPT" ]]; then
  echo "Error: Demo script not found or not executable. Run ./setup.sh first."
  exit 1
fi

exec bash "$DEMO_SCRIPT"
