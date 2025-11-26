#!/bin/bash

# Blockchain Demo Startup Script
# This script starts all blockchain services using docker-compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting Blockchain Demo Services..."
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose not found. Please install docker-compose."
    exit 1
fi

# Check if containers are already running
if docker ps --format '{{.Names}}' | grep -q "^blockchain_"; then
    echo "⚠️  Blockchain containers are already running."
    echo "   Restarting services..."
    docker-compose restart
    echo ""
    echo "⏳ Waiting for services to reinitialize..."
    sleep 5
else
    # Start services
    docker-compose up -d
    
    echo ""
    echo "⏳ Waiting for services to initialize..."
    sleep 10
fi

echo ""
echo "✅ Services started!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔗 Node APIs:"
echo "   Node 1: http://localhost:3001"
echo "   Node 2: http://localhost:3002"
echo "   Node 3: http://localhost:3003"
echo ""
echo "Use 'docker-compose logs -f' to view logs"
echo "Use 'docker-compose down' to stop services"

