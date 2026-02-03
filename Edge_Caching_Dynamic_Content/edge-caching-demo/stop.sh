#!/bin/bash

set -e

echo "🛑 Stopping Edge Caching Dynamic Content Demo..."
echo "================================================"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
  DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
  DOCKER_COMPOSE_CMD="docker compose"
fi

if [ -n "$DOCKER_COMPOSE_CMD" ] && [ -f "docker-compose.yml" ]; then
    $DOCKER_COMPOSE_CMD down 2>/dev/null || true
    echo "✅ Containers stopped"
else
    echo "⚠️  docker-compose not found or docker-compose.yml missing"
fi
