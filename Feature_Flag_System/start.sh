#!/bin/bash

echo "=== Starting Feature Flag System ==="
echo ""

# Check if flag-system directory exists
if [ ! -d "flag-system" ]; then
    echo "Error: flag-system directory not found."
    echo "Please run ./setup.sh first to generate all files."
    exit 1
fi

cd flag-system

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "Error: docker-compose.yml not found."
    echo "Please run ./setup.sh first."
    exit 1
fi

echo "Starting services..."
docker-compose up -d postgres redis flag-service checkout-service payment-service recommendations-service dashboard

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Services started successfully!"
    echo ""
    echo "Waiting for services to be ready..."
    sleep 5
    
    echo ""
    echo "Service Status:"
    docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}"
    
    echo ""
    echo "=== Services Running ==="
    echo "🎯 Dashboard: http://localhost:8080"
    echo "🚩 Flag Service API: http://localhost:3000"
    echo ""
    echo "To view logs: cd flag-system && docker-compose logs -f"
    echo "To stop services: cd flag-system && docker-compose down"
    echo ""
else
    echo ""
    echo "✗ Failed to start services. Check the errors above."
    exit 1
fi


