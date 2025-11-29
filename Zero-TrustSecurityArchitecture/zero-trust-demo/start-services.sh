#!/bin/bash

# Zero-Trust Security Architecture - Service Startup Script
# This script starts all services using Docker Compose

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================="
echo "Starting Zero-Trust Architecture Services"
echo "=================================="

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed or not in PATH"
    exit 1
fi

# Use docker compose (newer) or docker-compose (older)
if command -v docker &> /dev/null && docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' is available"
    exit 1
fi

echo "Using: $COMPOSE_CMD"
echo ""

# Check if services are already running
if $COMPOSE_CMD ps | grep -q "Up"; then
    echo "Some services are already running. Stopping them first..."
    $COMPOSE_CMD down
    sleep 2
fi

echo "Starting services..."
$COMPOSE_CMD up -d

echo ""
echo "Waiting for services to be ready..."
sleep 15

echo ""
echo "Checking service health..."
$COMPOSE_CMD ps

echo ""
echo "=================================="
echo "Services started successfully!"
echo "=================================="
echo ""
echo "Dashboard: http://localhost:3000"
echo ""
echo "Services:"
echo "- Identity Provider: http://localhost:3001"
echo "- Policy Engine: http://localhost:3002"
echo "- Access Proxy: http://localhost:3003"
echo "- Protected Service: http://localhost:3004"
echo ""
echo "To view logs: $COMPOSE_CMD logs -f"
echo "To stop services: $COMPOSE_CMD down"
echo ""

