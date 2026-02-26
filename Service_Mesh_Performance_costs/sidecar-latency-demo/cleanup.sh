#!/bin/bash
# =============================================================================
# sidecar-latency-demo — cleanup script
# Stops all containers, prunes Docker resources, removes dev/cache artifacts
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$SCRIPT_DIR"

echo "[cleanup] Stopping demo stack (if present)..."
if [[ -f "$DEMO_DIR/docker-compose.yml" ]]; then
  (cd "$DEMO_DIR" && docker compose down -v --remove-orphans 2>/dev/null) || true
fi

echo "[cleanup] Stopping all running containers..."
docker stop $(docker ps -q) 2>/dev/null || true

echo "[cleanup] Removing stopped containers..."
docker container prune -f

echo "[cleanup] Removing unused images..."
docker image prune -a -f

echo "[cleanup] Removing unused volumes..."
docker volume prune -f

echo "[cleanup] Removing unused networks..."
docker network prune -f

echo "[cleanup] Removing build cache..."
docker builder prune -f 2>/dev/null || true

echo "[cleanup] Removing project artifacts (node_modules, venv, .pytest_cache, .pyc, Istio)..."
find "$SCRIPT_DIR" -mindepth 1 -type d -name node_modules -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name venv -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name .pytest_cache -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -name "*.pyc" -delete 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type d -iname "*istio*" ! -path "*/.git/*" -exec rm -rf {} + 2>/dev/null || true
find "$SCRIPT_DIR" -mindepth 1 -type f -iname "*istio*" ! -path "*/.git/*" -delete 2>/dev/null || true

echo "[cleanup] Done."
