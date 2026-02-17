#!/bin/bash
# Run cloud-cost-optimizer tests.
# Run from cloud-cost-optimizer: ./test.sh
# Uses the running container if available; otherwise runs locally.

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [[ ! -f tests/fleet.test.js ]]; then
  echo "Error: Tests not found. Run setup.sh from repo root first."
  exit 1
fi

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx cloud-cost-optimizer; then
  echo "Running tests inside container..."
  docker exec cloud-cost-optimizer node tests/fleet.test.js
else
  echo "Container not running. Running tests locally..."
  if [[ ! -d node_modules ]]; then
    npm install --production
  fi
  node tests/fleet.test.js
fi
echo "OK: Tests completed"
