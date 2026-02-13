#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
echo "Starting GC Tuning demo from: $SCRIPT_DIR"
# Stop any existing stack to avoid duplicate services
docker compose down 2>/dev/null || true
docker compose up -d
echo "Waiting for services to be healthy..."
for i in $(seq 1 24); do
  if docker compose ps 2>/dev/null | grep -q "healthy"; then
    echo "Services ready."
    exit 0
  fi
  sleep 5
done
echo "⚠️  Some services may still be starting. Dashboard: http://localhost:3000"
