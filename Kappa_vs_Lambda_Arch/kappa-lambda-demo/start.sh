#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Starting Kappa vs Lambda Architecture Demo"
echo "=================================================="

# Check required files exist (run from project root after setup)
if [ ! -f "docker-compose.yml" ]; then
  echo "❌ Error: docker-compose.yml not found"
  echo "Please run setup.sh first: bash $(dirname "$0")/setup.sh"
  exit 1
fi

# Resolve docker-compose (full path when possible)
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
elif [ -f "/mnt/c/Program Files/Docker/Docker/resources/bin/docker-compose.exe" ]; then
  DOCKER_COMPOSE_CMD="/mnt/c/Program Files/Docker/Docker/resources/bin/docker-compose.exe"
fi

if [ -z "$DOCKER_COMPOSE_CMD" ]; then
  echo "❌ Error: docker-compose not found"
  echo "Please install Docker and ensure docker-compose is available"
  exit 1
fi

# Check Docker daemon
if ! $DOCKER_COMPOSE_CMD ps &> /dev/null 2>&1; then
  echo "❌ Error: Docker daemon is not running or not accessible"
  exit 1
fi

# Check for existing/duplicate containers - avoid starting duplicates
EXISTING=$($DOCKER_COMPOSE_CMD ps -q 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  echo ""
  echo "Found existing containers. Restarting services (no duplicate stack)..."
  $DOCKER_COMPOSE_CMD up -d
else
  echo ""
  echo "Building containers (if needed)..."
  $DOCKER_COMPOSE_CMD build
  echo ""
  echo "Starting services..."
  $DOCKER_COMPOSE_CMD up -d
fi

echo ""
echo "⏳ Waiting for services to be ready (35s for first batch + Kafka)..."
sleep 35

# Health checks
echo ""
echo "Checking service health..."
HEALTHY=false
for i in $(seq 1 30); do
  if curl -sf http://localhost:3005/health > /dev/null 2>&1 && \
     curl -sf http://localhost:3001/health > /dev/null 2>&1; then
    HEALTHY=true
    break
  fi
  sleep 1
done

if [ "$HEALTHY" = true ]; then
  echo "✅ Serving layer and producer are up"
else
  echo "⚠️  Some services may still be starting; dashboard may show zeros briefly"
fi

echo ""
echo "=================================================="
echo "✅ Demo started!"
echo "=================================================="
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo "   (Metrics update every 2s; run demo to see events)"
echo ""
echo "View logs:  $DOCKER_COMPOSE_CMD logs -f"
echo "Stop:      $DOCKER_COMPOSE_CMD down"
echo "=================================================="
