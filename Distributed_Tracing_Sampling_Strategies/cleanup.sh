#!/bin/bash
# Stop containers and remove unused Docker resources, then clean project cruft.
# Run from: Distributed_Tracing_Sampling_Strategies (or use full path to this script).

set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Stopping project containers ==="
if [ -d "tracing-sampling-demo" ]; then
  (cd tracing-sampling-demo && docker compose down -v --remove-orphans 2>/dev/null || docker-compose down -v --remove-orphans 2>/dev/null) || true
fi

echo "=== Removing unused Docker resources ==="
docker system prune -a -f --volumes 2>/dev/null || true

echo "=== Removing project cruft (node_modules, venv, .pytest_cache, .pyc, Istio) ==="
find "$SCRIPT_DIR" -type d -name "node_modules" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "venv" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name ".pytest_cache" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -path "*istio*" -type f -delete 2>/dev/null || true
find "$SCRIPT_DIR" -path "*istio*" -type d -empty -delete 2>/dev/null || true

echo "Done. To stop the Docker daemon: sudo systemctl stop docker"
