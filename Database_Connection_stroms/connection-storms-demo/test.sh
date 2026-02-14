#!/bin/bash
# Database Connection Storms Demo - Test script
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "======================================"
echo "Running Database Connection Storms Tests"
echo "======================================"

cd "$SCRIPT_DIR"

echo ""
echo "Running test suite..."
docker compose run --rm tests
