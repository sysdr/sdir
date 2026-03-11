#!/bin/bash
# ============================================================
# Log Aggregation at Scale — Cleanup script (main directory)
# Stops containers, removes unused Docker resources, and
# removes node_modules, venv, .pytest_cache, .pyc, Istio files
# ============================================================

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Stopping project containers ==="
docker-compose down -v --remove-orphans 2>/dev/null || true

echo "=== Removing project Docker images ==="
docker rmi log-aggregation-demo_load-generator log_aggregation_at_scale_load-generator 2>/dev/null || true

echo "=== Pruning unused Docker resources (containers, images, networks) ==="
docker system prune -af --volumes 2>/dev/null || true

echo "=== Removing node_modules, venv, .pytest_cache, .pyc, __pycache__, Istio files ==="
rm -rf node_modules
rm -rf venv .venv env
find . -type d -name ".pytest_cache" 2>/dev/null | xargs -r rm -rf
find . -type d -name "__pycache__" 2>/dev/null | xargs -r rm -rf
find . -type f -name "*.pyc" -delete 2>/dev/null || true
find . -type f -name "*.pyo" -delete 2>/dev/null || true
rm -rf istio .istio 2>/dev/null || true
find . -maxdepth 2 -type d -name "istio" 2>/dev/null | xargs -r rm -rf

echo "=== Cleanup complete ==="
