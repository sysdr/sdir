#!/bin/bash
# Start the Distributed Job Scheduler - use full path for reliability
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Starting Distributed Job Scheduler..."
docker compose up -d

echo "Waiting for services..."
sleep 5

echo "Dashboard: http://localhost:3000"
echo "Run ./demo.sh for live logs"
