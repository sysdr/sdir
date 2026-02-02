#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check for duplicate services (containers already running)
if docker-compose ps 2>/dev/null | grep -q "Up"; then
  echo "⚠️  Services are already running."
  echo "   Dashboard: http://localhost:3000"
  echo "   Run './cleanup.sh' first to stop, or './demo.sh' to trigger demo traffic."
  docker-compose ps
  exit 0
fi

# Check for port 3000 in use
if lsof -ti:3000 > /dev/null 2>&1; then
  echo "⚠️  Port 3000 is in use. Attempting to free..."
  lsof -ti:3000 | xargs kill -9 2>/dev/null || true
  sleep 2
fi

echo "🚀 Starting SSR vs CSR Demo services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
MAX_RETRIES=30
for i in $(seq 1 $MAX_RETRIES); do
  if curl -s http://localhost:3000/api/metrics > /dev/null 2>&1; then
    echo "✅ Service is ready!"
    break
  fi
  [ $i -eq $MAX_RETRIES ] && echo "⚠️  Service may still be starting. Check: docker-compose logs -f"
  sleep 1
done

echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔵 SSR Demo: http://localhost:3000/api/ssr"
echo "🔴 CSR Demo: http://localhost:3000/api/csr"
echo ""
echo "Run './demo.sh' to trigger traffic and update metrics."
echo "Run './tests/test.sh' to validate."
