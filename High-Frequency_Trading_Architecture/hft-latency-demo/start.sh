#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
echo "Starting HFT Latency Demo from $SCRIPT_DIR"
docker-compose up -d
echo "Services started. Dashboard: http://localhost:3000"
