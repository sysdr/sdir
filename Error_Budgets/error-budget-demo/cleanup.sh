#!/bin/bash

echo "🧹 Cleaning up Error Budget Demo..."

# Stop and remove containers
docker-compose down --remove-orphans --volumes 2>/dev/null || true

# Remove Docker images
docker-compose down --rmi all --volumes --remove-orphans 2>/dev/null || true

# Clean up Docker system
docker system prune -f >/dev/null 2>&1 || true

echo "✅ Cleanup completed!"
echo ""
echo "To run the demo again:"
echo "  ./demo.sh"
