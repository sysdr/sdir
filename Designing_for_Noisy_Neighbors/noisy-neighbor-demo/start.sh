#!/bin/bash
# Start the Noisy Neighbor demo stack. Run from noisy-neighbor-demo (or: bash noisy-neighbor-demo/start.sh)
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
API_PORT="${API_PORT:-3001}"
if [ ! -f "docker-compose.yml" ]; then
  echo "Error: Demo not set up. Run ./setup.sh from project root first."
  exit 1
fi
echo "Stopping any existing demo containers..."
docker compose down -v --remove-orphans 2>/dev/null || true
docker stop nn-redis nn-api nn-loadgen 2>/dev/null || true
docker rm nn-redis nn-api nn-loadgen 2>/dev/null || true
echo "Starting Redis..."
docker compose up -d redis
for i in $(seq 1 20); do
  docker exec nn-redis redis-cli ping >/dev/null 2>&1 && break
  sleep 1
done
echo "Redis ready."
echo "Starting API..."
docker compose up -d api
for i in $(seq 1 40); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' nn-api 2>/dev/null || true)
  [ "$STATUS" = "healthy" ] && break
  sleep 2
done
echo "API ready."
echo "Starting load generator..."
docker compose up -d loadgen
echo "Load generator started."
echo ""
echo "Demo is running."
echo "  Dashboard:  http://localhost:${API_PORT}"
echo "  Metrics:    http://localhost:${API_PORT}/metrics"
echo "  Health:     http://localhost:${API_PORT}/health"
echo ""
echo "To stop: bash cleanup.sh (from this dir) or: docker compose down"
echo ""
