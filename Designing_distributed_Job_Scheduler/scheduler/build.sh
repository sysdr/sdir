#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Building Distributed Job Scheduler"
echo "=================================================="

echo ""
echo "Building Docker containers..."
docker compose build

echo ""
echo "=================================================="
echo "Build completed successfully!"
echo "=================================================="
echo ""
echo "To start: ./start.sh or docker compose up -d"
echo "To run tests: docker compose run --rm tests"
echo "=================================================="
