#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

# Check for duplicate services (containers already running)
if docker-compose ps 2>/dev/null | grep -q "Up"; then
  echo "Services are already running."
  echo "Dashboard: http://localhost:3002"
  echo "Run './cleanup.sh' first to stop, or './demo.sh' to view logs."
  exit 0
fi

echo "Starting Watermark Demo services..."
docker-compose up -d

echo ""
echo "Waiting for services to be healthy..."
sleep 10

if docker-compose ps | grep -q "unhealthy"; then
  echo "Warning: Some services may still be starting. Check with: docker-compose ps"
fi

echo ""
echo "✓ Services started. Dashboard: http://localhost:3002"
echo "Run './tests/test.sh' to verify. Run './demo.sh' to watch logs."
