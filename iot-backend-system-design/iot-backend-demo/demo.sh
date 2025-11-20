#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cd "$PROJECT_DIR"

echo "🔨 Building containers..."
docker compose build --quiet

echo "🚀 Starting IoT Backend System..."
docker compose up -d

echo "⏳ Waiting for services to start..."
sleep 10

echo "🏥 Running health checks..."
for _ in {1..10}; do
  if curl -s http://localhost:3001/health >/dev/null 2>&1; then
    echo "✅ Backend is healthy"
    break
  fi
  sleep 2
done

echo ""
echo "🧪 Running tests..."
if ! docker compose exec -T backend npm test; then
  echo "⚠️ Tests reported failures. Inspect logs above."
fi

echo ""
echo "=============================================="
echo "✅ IoT Backend System is running!"
echo ""
echo "📊 Dashboard:    http://localhost:3000"
echo "🔌 Backend API:  http://localhost:3001"
echo "📡 MQTT Broker:  localhost:1883"
echo ""
echo "🔍 Test Commands:"
echo "  curl http://localhost:3001/api/devices"
echo "  curl http://localhost:3001/api/stats"
echo ""
echo "📝 View logs:    docker compose logs -f"
echo "🧹 Cleanup:      ./cleanup.sh"
echo "=============================================="
