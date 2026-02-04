#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "MQTT vs CoAP Demo - Full Cleanup"
echo "=========================================="

# 1. Stop all containers
echo ""
echo "Stopping containers..."
docker-compose down -v 2>/dev/null || true
docker stop $(docker ps -aq) 2>/dev/null || true

# 2. Remove unused Docker resources
echo ""
echo "Removing unused Docker resources..."
docker container prune -f 2>/dev/null || true
docker image prune -af 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
docker network prune -f 2>/dev/null || true
docker system prune -af 2>/dev/null || true

# 3. Remove project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)
echo ""
echo "Removing project artifacts..."
find "$SCRIPT_DIR" -type d -name "node_modules" 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true
find "$SCRIPT_DIR" -type d -name "venv" 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true
find "$SCRIPT_DIR" -type d -name ".pytest_cache" 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true
find "$SCRIPT_DIR" -type d -name "__pycache__" 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true
find "$SCRIPT_DIR" -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -iname "*istio*" -type f -delete 2>/dev/null || true
find "$SCRIPT_DIR" -type d -iname "*istio*" 2>/dev/null | while read d; do rm -rf "$d" 2>/dev/null; done || true

echo ""
echo "Cleanup complete!"
