#!/bin/bash

echo "Cleaning up Low-Latency Trading System..."
echo "========================================"

cd low-latency-trading 2>/dev/null || {
  echo "Project directory not found"
  exit 0
}

echo "Stopping containers..."
docker-compose down -v

cd ..
echo "Removing project files..."
rm -rf low-latency-trading

echo ""
echo "Cleanup complete! ✓"
