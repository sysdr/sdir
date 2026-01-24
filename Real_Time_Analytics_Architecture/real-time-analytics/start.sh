#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Starting Real-Time Analytics Services"
echo "=================================================="

# Check for docker-compose with full path
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
  echo "Please install Docker Desktop and ensure WSL integration is enabled"
  exit 1
fi

# Check if Docker daemon is running
if ! "$DOCKER_COMPOSE_CMD" ps &> /dev/null; then
  echo "❌ Error: Docker daemon is not running"
  echo "Please start Docker Desktop and ensure WSL integration is enabled"
  exit 1
fi

# Check for duplicate services
echo ""
echo "Checking for existing services..."
EXISTING_CONTAINERS=$("$DOCKER_COMPOSE_CMD" ps -q 2>/dev/null || echo "")
if [ -n "$EXISTING_CONTAINERS" ]; then
  echo "⚠️  Warning: Found existing containers"
  "$DOCKER_COMPOSE_CMD" ps
  echo ""
  read -p "Stop existing containers and start fresh? (y/n) " -n 1 -r
  echo
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Stopping existing containers..."
    "$DOCKER_COMPOSE_CMD" down
  else
    echo "Using existing containers..."
    "$DOCKER_COMPOSE_CMD" up -d
    exit 0
  fi
fi

# Build and start services
echo ""
echo "Building Docker containers..."
"$DOCKER_COMPOSE_CMD" build

echo ""
echo "Starting services..."
"$DOCKER_COMPOSE_CMD" up -d

echo ""
echo "Waiting for services to be ready..."
sleep 10

# Check service health
echo ""
echo "Checking service health..."
for i in {1..30}; do
  if curl -s http://localhost:3001/health > /dev/null 2>&1 && \
     curl -s http://localhost:3002/health > /dev/null 2>&1; then
    echo "✅ All services are healthy"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "⚠️  Warning: Services may not be fully ready yet"
  else
    sleep 1
  fi
done

echo ""
echo "=================================================="
echo "✅ Services Started Successfully!"
echo "=================================================="
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔌 Ingestion API: http://localhost:3001"
echo "📈 Query API: http://localhost:3002"
echo ""
echo "View logs: $DOCKER_COMPOSE_CMD logs -f"
echo "Stop services: $DOCKER_COMPOSE_CMD down"
echo "=================================================="


