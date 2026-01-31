#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "docker-compose.yml" ]; then
  echo "❌ docker-compose.yml not found. Run setup.sh first."
  exit 1
fi

if command -v docker-compose &> /dev/null; then
  docker-compose build
elif command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
  docker compose build
else
  echo "❌ docker-compose not found"
  exit 1
fi

echo "✅ Build complete"
