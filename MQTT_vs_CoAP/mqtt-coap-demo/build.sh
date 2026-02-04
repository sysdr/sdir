#!/bin/bash

set -e

echo "=== Building MQTT vs CoAP Demo ==="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "docker-compose.yml" ]; then
    echo "Error: docker-compose.yml not found. Run ../setup.sh first."
    exit 1
fi

echo "Building Docker containers..."
docker-compose build

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Build completed successfully!"
    echo ""
    echo "To start services: ./start.sh"
    echo "To run tests:      ./test.sh"
    echo "To validate:       ./validate.sh"
    echo ""
else
    echo ""
    echo "✗ Build failed. Check the errors above."
    exit 1
fi
