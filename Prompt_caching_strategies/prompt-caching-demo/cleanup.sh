#!/bin/bash
# Cleanup: stop containers, remove unused Docker resources, and optional project cruft.
# Run from this directory: ./cleanup.sh

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Stopping demo stack ==="
docker compose down -v --remove-orphans 2>/dev/null || true
docker rmi prompt-caching-demo-backend prompt-caching-demo-frontend 2>/dev/null || true

echo "=== Stopping all running containers ==="
docker stop $(docker ps -q) 2>/dev/null || true

echo "=== Removing unused Docker resources ==="
docker system prune -af --volumes 2>/dev/null || true
docker container prune -f 2>/dev/null || true
docker image prune -af 2>/dev/null || true
docker network prune -f 2>/dev/null || true

echo "=== Removing node_modules, venv, .pytest_cache, .pyc, Istio artifacts ==="
find . -type d -name "node_modules" 2>/dev/null | while read -r d; do rm -rf "$d"; done
find . -type d -name "venv" 2>/dev/null | while read -r d; do rm -rf "$d"; done
find . -type d -name ".pytest_cache" 2>/dev/null | while read -r d; do rm -rf "$d"; done
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type d -name "__pycache__" 2>/dev/null | while read -r d; do rm -rf "$d"; done
find . -iname "*istio*" -type f -delete 2>/dev/null || true
find . -type d -iname "*istio*" 2>/dev/null | while read -r d; do rm -rf "$d"; done

echo "=== Done ==="
echo "To stop the Docker daemon (optional): sudo systemctl stop docker"
