#!/bin/bash

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║           Cleaning up Cascading Timeouts Demo                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if we're in the demo directory
if [ ! -f "docker-compose.yml" ]; then
    if [ -d "cascading-timeouts-demo" ]; then
        cd cascading-timeouts-demo
    else
        echo "❌ Error: Cannot find demo directory"
        echo "   Please run this script from the same location as demo.sh"
        exit 1
    fi
fi

echo "🛑 Stopping all containers..."
docker-compose down

echo ""
echo "🗑️  Removing Docker images..."
docker-compose down --rmi all --volumes --remove-orphans

echo ""
echo "📁 Cleaning up project files..."


echo ""
echo "✅ Cleanup complete!"
echo ""
echo "All containers, images, and project files have been removed."
echo "Run ./demo.sh again anytime to recreate the demo."
echo ""