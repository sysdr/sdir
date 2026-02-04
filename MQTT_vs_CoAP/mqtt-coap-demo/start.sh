#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "docker-compose.yml" ]; then
    echo "Error: docker-compose.yml not found. Run setup.sh first."
    exit 1
fi

# Check for duplicate/existing containers
RUNNING=$(docker-compose ps -q 2>/dev/null | wc -l)
if [ "$RUNNING" -gt 0 ]; then
    echo "Services already running. Use 'docker-compose restart' or 'docker-compose down' first."
    docker-compose ps
    exit 0
fi

echo "Starting MQTT vs CoAP demo..."
docker-compose up -d

echo "Waiting for services..."
sleep 8

echo "Dashboard: http://localhost:3000"
echo "Run: bash test.sh to verify"
