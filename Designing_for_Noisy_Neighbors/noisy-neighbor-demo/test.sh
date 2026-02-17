#!/bin/bash
# Run integration tests. Run from noisy-neighbor-demo. API must be running (./start.sh).
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
if [ ! -f "docker-compose.yml" ]; then
  echo "Error: Demo not set up. Run ./setup.sh from project root first."
  exit 1
fi
if ! docker ps --format '{{.Names}}' | grep -qx nn-api; then
  echo "Error: API container (nn-api) is not running. Run ./start.sh first."
  exit 1
fi
LOADGEN_WAS_UP=false
if docker ps --format '{{.Names}}' | grep -qx nn-loadgen; then
  LOADGEN_WAS_UP=true
  docker stop nn-loadgen 2>/dev/null || true
  sleep 1
fi
echo "Running integration tests..."
EXIT=0
docker exec nn-api node tests.js || EXIT=$?
if [ "$LOADGEN_WAS_UP" = true ]; then
  echo "Restarting load generator..."
  docker compose up -d loadgen 2>/dev/null || true
fi
exit $EXIT
