#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IAC_DEMO_DIR="${SCRIPT_DIR}/iac-demo"

if [ ! -d "$IAC_DEMO_DIR" ]; then
  echo "Error: iac-demo directory not found. Please run setup.sh first."
  exit 1
fi

cd "$IAC_DEMO_DIR"

echo "Starting Infrastructure as Code Demo..."
echo "========================================"

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
  echo "Error: docker-compose not found"
  exit 1
fi

# Check for running containers
if docker-compose ps 2>/dev/null | grep -q "Up"; then
  echo "Services are already running. Stopping existing services..."
  docker-compose down
fi

echo "Building containers..."
docker-compose build

echo "Starting services..."
docker-compose up -d

echo "Waiting for services to be ready..."
sleep 15

# Check health
echo "Checking service health..."
BACKEND_HEALTH=$(curl -s http://localhost:3001/health || echo "failed")
if echo "$BACKEND_HEALTH" | grep -q "healthy"; then
  echo "✓ Backend is healthy"
else
  echo "✗ Backend health check failed"
fi

echo ""
echo "========================================"
echo "Demo is ready!"
echo "========================================"
echo "Dashboard: http://localhost:3000"
echo "Backend API: http://localhost:3001"
echo ""
echo "To stop services, run: cd iac-demo && docker-compose down"
