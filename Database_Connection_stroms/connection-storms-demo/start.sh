#!/bin/bash
# Start Database Connection Storms Demo
# Run from this script's directory or use full path
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Stopping any existing containers..."
docker compose down 2>/dev/null || true

echo "Starting services..."
docker compose up -d postgres pgbouncer backend frontend

echo "Waiting for services to be healthy (~60s)..."
sleep 60

echo "Running demo to populate metrics..."
bash "$SCRIPT_DIR/demo.sh"

echo "Running tests..."
docker compose run --rm tests

echo ""
echo "Dashboard: http://localhost:3000"
echo "Backend API: http://localhost:3001"
echo ""
echo "To trigger storms manually, use the Storm Simulator in the dashboard."
