#!/bin/bash
# Full cycle: stop existing demo, run setup (create + build + start), then run tests.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/expand-contract-demo/setup.sh" ]; then
  DEMO_DIR="$SCRIPT_DIR"
  SETUP_SH="$SCRIPT_DIR/expand-contract-demo/setup.sh"
else
  DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
  SETUP_SH="$SCRIPT_DIR/setup.sh"
fi

echo "▶  Stopping any existing demo containers..."
(cd "$DEMO_DIR" 2>/dev/null && docker compose down -v --remove-orphans 2>/dev/null) || true

echo ""
echo "▶  Running setup (create demo, build, start)..."
bash "$SETUP_SH"

echo ""
echo "▶  Running tests..."
bash "$SCRIPT_DIR/test.sh"

echo ""
echo "✅ Done. Dashboard: http://localhost:3000"
