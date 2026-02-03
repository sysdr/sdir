#!/bin/bash

set -e

echo "🚀 Starting Edge Caching Dynamic Content Demo..."
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "docker-compose.yml" ]; then
    echo "⚠️  docker-compose.yml not found. Run setup.sh from project root first."
    exit 1
fi

DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
fi

if [ -z "$DOCKER_COMPOSE_CMD" ]; then
  echo "❌ Error: docker-compose not found"
  exit 1
fi

echo ""
echo "🔍 Checking for existing Edge Caching containers..."
EXISTING=$(docker ps --format "{{.Names}}" | grep -E "edge-(origin|us-west|us-east|eu|dashboard|load-generator|redis)" || true)
if [ -n "$EXISTING" ]; then
    echo "⚠️  Found existing containers. Stopping them first..."
    $DOCKER_COMPOSE_CMD down 2>/dev/null || true
    sleep 3
fi

echo ""
echo "🚀 Starting services..."
$DOCKER_COMPOSE_CMD up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 12

echo ""
echo "✅ Checking service status..."
$DOCKER_COMPOSE_CMD ps

echo ""
echo "📊 Validating services..."
sleep 3
if curl -s http://localhost:3000 > /dev/null 2>&1; then
    echo "✅ Dashboard is responding"
else
    echo "⚠️  Dashboard not responding yet (may need more time)"
fi

echo ""
echo "================================================"
echo "✅ Services started successfully!"
echo "================================================"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo ""
echo "📋 Useful commands:"
echo "  • View logs: $DOCKER_COMPOSE_CMD logs -f"
echo "  • Stop: bash $SCRIPT_DIR/stop.sh"
echo "  • Status: $DOCKER_COMPOSE_CMD ps"
echo ""
