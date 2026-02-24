#!/bin/bash
# Start the demo. Demo content (docker-compose) lives in project root.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/expand-contract-demo/setup.sh" ]; then
  DEMO_DIR="$SCRIPT_DIR"
else
  DEMO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

if [ ! -f "$DEMO_DIR/docker-compose.yml" ]; then
  echo "Demo not found. Run ./setup.sh or ./build.sh first."
  exit 1
fi

cd "$DEMO_DIR"
docker compose up -d
echo "Demo services started. Dashboard: http://localhost:3000"
