#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Starting Edge Computing Architecture Demo"
echo "=================================================="
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    echo "Error: docker-compose or docker is not installed"
    exit 1
fi

# Check if services are already running
if docker-compose ps | grep -q "Up"; then
    echo "Services are already running. Use 'docker-compose restart' to restart them."
    docker-compose ps
    exit 0
fi

# Start services
echo "Starting Docker containers..."
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
else
    docker compose up -d
fi

echo ""
echo "Waiting for services to be healthy..."
sleep 15

# Check service health
echo ""
echo "Checking service health..."
for port in 3001 3002 3003; do
    if curl -s http://localhost:$port/health > /dev/null; then
        echo "✓ Service on port $port is healthy"
    else
        echo "✗ Service on port $port is not responding"
    fi
done

echo ""
echo "=================================================="
echo "Services are running!"
echo "=================================================="
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo "📱 Device Edge API: http://localhost:3001"
echo "🌍 Regional Edge API: http://localhost:3002"
echo "☁️  Central Cloud API: http://localhost:3003"
echo ""
echo "To view logs: docker-compose logs -f"
echo "To stop services: docker-compose down"
echo ""

