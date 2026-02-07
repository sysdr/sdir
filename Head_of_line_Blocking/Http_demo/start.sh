#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "docker-compose.yml" ]; then
  echo "❌ Error: docker-compose.yml not found. Run ./setup.sh first."
  exit 1
fi

# Check for duplicate services
RUNNING=$(docker-compose ps -q 2>/dev/null | wc -l)
if [ "$RUNNING" -gt 0 ]; then
  echo "⚠️  Services already running. Use 'docker-compose restart' or 'docker-compose down' first."
  docker-compose ps
  exit 0
fi

echo "🚀 Starting Head-of-Line Blocking Demo..."
docker-compose up -d

echo "⏳ Waiting for services..."
sleep 5

echo ""
echo "✅ Services started!"
echo "   Dashboard: http://127.0.0.1:3000"
echo "   HTTP/2:    http://127.0.0.1:8443/stats"
echo "   HTTP/3:    http://127.0.0.1:8444/stats"
echo ""
echo "   Run: bash run-load-test.sh (to generate traffic for dashboard)"
echo "   Run: bash demo.sh (for live logs)"
