#!/bin/bash
set -euo pipefail

# Build the Expand-Contract demo. If docker-compose is not in project root, run setup first.
# Demo content lives in project root; only setup.sh stays in expand-contract-demo/.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/expand-contract-demo/setup.sh" ]; then
  DEMO_DIR="$SCRIPT_DIR"
  SETUP_SH="$SCRIPT_DIR/expand-contract-demo/setup.sh"
else
  DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  SETUP_SH="$SCRIPT_DIR/setup.sh"
fi

if [ ! -f "$DEMO_DIR/docker-compose.yml" ]; then
  echo "▶  Demo not found. Running setup first..."
  bash "$SETUP_SH"
  exit 0
fi

echo "▶  Building Docker images..."
cd "$DEMO_DIR"
docker compose build "$@"
echo "✅ Build complete. Start with: bash $DEMO_DIR/start.sh"
