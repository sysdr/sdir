#!/bin/bash
# Start the cloud-cost-optimizer container.
# Run from cloud-cost-optimizer: ./start.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v docker &>/dev/null; then
  echo "Error: Docker not found."
  exit 1
fi

if ! docker image inspect cloud-cost-optimizer &>/dev/null; then
  echo "Error: Image cloud-cost-optimizer not found. Run ./build.sh first."
  exit 1
fi

# Stop and remove existing container
docker stop cloud-cost-optimizer 2>/dev/null && echo "Stopped existing container" || true
docker rm   cloud-cost-optimizer 2>/dev/null || true

# Warn if port 3000 is in use by something other than docker
if command -v ss &>/dev/null; then
  OTHER=$(ss -tlnp 2>/dev/null | grep -E ':3000\s' | grep -v docker || true)
elif command -v netstat &>/dev/null; then
  OTHER=$(netstat -tlnp 2>/dev/null | grep -E ':3000\s' | grep -v docker || true)
fi
if [[ -n "$OTHER" ]]; then
  echo "Warning: Port 3000 may be in use:"
  echo "$OTHER"
fi

docker run -d \
  --name cloud-cost-optimizer \
  -p 3000:3000 \
  --restart unless-stopped \
  cloud-cost-optimizer

echo "OK: Container started: cloud-cost-optimizer"
echo "Waiting for service..."
MAX=30
COUNT=0
until curl -sf http://localhost:3000/health >/dev/null 2>&1; do
  COUNT=$((COUNT + 1))
  if [[ $COUNT -ge $MAX ]]; then
    echo "Timeout waiting for health check. Check: docker logs cloud-cost-optimizer"
    exit 1
  fi
  printf "."
  sleep 1
done
echo ""
echo "OK: Service is healthy"
echo "Dashboard: http://localhost:3000"
