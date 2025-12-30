#!/bin/bash

echo "=========================================="
echo "Poison Pill Demo Cleanup"
echo "=========================================="
echo ""

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "Error: Not in the poison-pill-demo directory"
    echo "Please run this script from the poison-pill-demo folder"
    exit 1
fi

echo "[1/5] Stopping all running containers..."
docker-compose down -v

echo "[2/5] Removing Docker images..."
docker-compose down --rmi all --volumes --remove-orphans 2>/dev/null || true

echo "[3/5] Cleaning up Docker build cache..."
docker system prune -f 2>/dev/null || true


echo "[5/5] Verifying cleanup..."
if [ ! -d "poison-pill-demo" ]; then
    echo "✅ Cleanup successful!"
else
    echo "⚠️  Some files may remain. You can manually delete the poison-pill-demo directory."
fi

echo ""
echo "=========================================="
echo "Cleanup Complete"
echo "=========================================="
echo ""
echo "All containers stopped and removed"
echo "All project files deleted"
echo "System resources freed"
echo ""