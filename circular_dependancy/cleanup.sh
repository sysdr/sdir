#!/bin/bash

echo "🧹 Cleaning up Circular Dependencies Demo"
echo "=========================================="

cd circular-deps-demo 2>/dev/null || {
    echo "❌ Demo directory not found. Nothing to clean up."
    exit 0
}

echo "🛑 Stopping Docker containers..."
docker-compose down -v 2>/dev/null || echo "No containers to stop"

echo "🗑️  Removing Docker images..."
docker rmi circular-deps-demo-user-service 2>/dev/null || echo "User service image not found"
docker rmi circular-deps-demo-order-service 2>/dev/null || echo "Order service image not found"
docker rmi circular-deps-demo-inventory-service 2>/dev/null || echo "Inventory service image not found"

echo "🧹 Removing project files..."
cd ..

echo ""
echo "✅ Cleanup complete!"
echo "All demo files and containers have been removed."
echo ""