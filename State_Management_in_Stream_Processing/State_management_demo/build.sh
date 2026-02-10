#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Building State Management in Stream Processing"
echo "=================================================="

if [ ! -f "docker-compose.yml" ]; then
  echo "❌ Error: docker-compose.yml not found"
  echo "Please run ./setup.sh first to generate the project files"
  exit 1
fi

DC_CMD=""
if command -v docker-compose &>/dev/null; then
  DC_CMD="docker-compose"
elif docker compose version &>/dev/null 2>&1; then
  DC_CMD="docker compose"
fi

if [ -z "$DC_CMD" ]; then
  echo "❌ Error: docker-compose not found"
  exit 1
fi

if ! $DC_CMD ps &>/dev/null; then
  echo "❌ Error: Docker daemon is not running"
  exit 1
fi

echo ""
echo "Building Docker containers..."
echo ""

$DC_CMD build

echo ""
echo "=================================================="
echo "✅ Build completed successfully!"
echo "=================================================="
echo ""
echo "To start: ./start.sh"
echo "=================================================="
