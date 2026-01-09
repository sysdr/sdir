#!/bin/bash

echo "=== Feature Flag System - Continuous Demo ==="
echo ""
echo "This script will continuously generate evaluation traffic"
echo "to keep dashboard metrics updated."
echo ""
echo "Dashboard: http://localhost:8080"
echo "Flag Service API: http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Check if flag-system directory exists
if [ ! -d "flag-system" ]; then
    echo "Error: flag-system directory not found."
    echo "Please run ./setup.sh first."
    exit 1
fi

# Check if services are running
if ! docker-compose -f flag-system/docker-compose.yml ps 2>/dev/null | grep -q "Up"; then
    echo "Services are not running. Starting services..."
    cd flag-system
    docker-compose up -d postgres redis flag-service checkout-service payment-service recommendations-service dashboard
    echo "Waiting for services to be ready..."
    sleep 5
    cd ..
fi

# Run the demo script from flag-system directory
cd flag-system
exec ./run-demo.sh


