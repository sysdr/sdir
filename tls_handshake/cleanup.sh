#!/bin/bash

# TLS Handshake Latency Demo Cleanup
# This script removes all demo components and cleans up Docker resources

set -e

echo "🧹 Cleaning up TLS Handshake Latency Demo..."
echo ""

PROJECT_DIR="tls-handshake-demo"

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Demo directory not found. Nothing to clean up."
    exit 0
fi

cd $PROJECT_DIR

# Stop and remove Docker containers
echo "🛑 Stopping Docker containers..."
docker-compose down -v 2>/dev/null || true

# Remove Docker images
echo "🗑️  Removing Docker images..."
docker rmi tls-handshake-demo-backend:latest 2>/dev/null || true
docker rmi tls-handshake-demo-dashboard:latest 2>/dev/null || true
docker rmi tls-handshake-demo-load-generator:latest 2>/dev/null || true

# Remove Docker network
echo "🌐 Removing Docker network..."
docker network rm tls-handshake-demo_tls-demo 2>/dev/null || true

# Go back and remove project directory

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "All demo components have been removed:"
echo "  • Docker containers stopped and removed"
echo "  • Docker images deleted"
echo "  • Docker networks cleaned up"
echo "  • Project files deleted"
echo ""
echo "You can run ./demo.sh again to recreate the demo."