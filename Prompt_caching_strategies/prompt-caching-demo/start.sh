#!/bin/bash
# Start the Prompt Caching demo stack. Run from this directory: ./start.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "docker-compose.yml" ]; then
  echo "Error: docker-compose.yml not found. Run ../setup.sh first."
  exit 1
fi

echo "Starting services..."
docker compose up -d

echo ""
echo "Dashboard: http://localhost:4210"
echo "To stop: ./cleanup.sh"
