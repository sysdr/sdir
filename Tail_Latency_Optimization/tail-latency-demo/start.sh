#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Checking for existing services on ports 3000 and 3001..."
if command -v lsof >/dev/null 2>&1; then
  if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Port 3000 already in use (dashboard may be running). Use cleanup.sh to stop."
    exit 1
  fi
  if lsof -Pi :3001 -sTCP:LISTEN -t >/dev/null 2>&1; then
    echo "Port 3001 already in use (API may be running). Use cleanup.sh to stop."
    exit 1
  fi
fi

echo "Starting services..."
docker-compose up -d

echo "Waiting for API to be ready..."
for i in {1..30}; do
  if curl -s http://localhost:3001/api/metrics >/dev/null 2>&1; then
    echo "API is ready."
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "API did not become ready in time."
    exit 1
  fi
  sleep 1
done

echo "Seeding demo load (50 requests) so dashboard shows non-zero metrics..."
for i in $(seq 1 50); do
  curl -s http://localhost:3001/api/request >/dev/null &
done
wait
echo "Demo seed complete. Open http://localhost:3000"

echo ""
echo "Dashboard: http://localhost:3000"
echo "API: http://localhost:3001"
