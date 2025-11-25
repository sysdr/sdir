#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname "$0")" >/dev/null 2>&1 && pwd)"
PROJECT_DIR="$ROOT_DIR/low-latency-trading"

if [ ! -d "$PROJECT_DIR" ]; then
  echo "Project directory not found at $PROJECT_DIR"
  echo "Run setup.sh first to generate all required files."
  exit 1
fi

echo "Starting Low-Latency Trading System demo..."
echo "Project directory: $PROJECT_DIR"

pushd "$PROJECT_DIR" >/dev/null

echo "Bringing up services via docker-compose..."
docker-compose up -d

echo "Waiting for services to initialize..."
sleep 5

if [ -x "./test.sh" ]; then
  echo "Running test suite..."
  ./test.sh
else
  echo "Warning: test.sh not found or not executable."
fi

echo "Services are running:"
docker-compose ps

popd >/dev/null

echo ""
echo "Dashboard:      http://localhost:3000"
echo "Market Data:    http://localhost:3001/health"
echo "Order Engine:   http://localhost:3002/health"
echo "Risk Manager:   http://localhost:3003/health"
