#!/bin/bash

echo "=== Building Feature Flag System ==="
echo ""

# Check if flag-system directory exists
if [ ! -d "flag-system" ]; then
    echo "Error: flag-system directory not found."
    echo "Please run ./setup.sh first to generate all files."
    exit 1
fi

cd flag-system

echo "Building Docker containers..."
docker-compose build

if [ $? -eq 0 ]; then
    echo ""
    echo "✓ Build completed successfully!"
    echo ""
    echo "To start services, run:"
    echo "  cd flag-system && docker-compose up -d"
    echo ""
else
    echo ""
    echo "✗ Build failed. Check the errors above."
    exit 1
fi


