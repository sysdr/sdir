#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

echo "[cleanup] Root: $ROOT_DIR"

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo "[cleanup] Docker Compose not found; skipping compose down."
  DC=""
fi

if [[ -n "${DC}" && -f "$ROOT_DIR/federated-learning-demo/docker-compose.yml" ]]; then
  echo "[cleanup] Stopping federated-learning-demo stack..."
  (cd "$ROOT_DIR/federated-learning-demo" && $DC down -v --remove-orphans) || true
fi

echo "[cleanup] Stopping all running containers..."
docker stop $(docker ps -q) 2>/dev/null || true

echo "[cleanup] Removing all containers..."
docker rm -f $(docker ps -aq) 2>/dev/null || true

echo "[cleanup] Pruning unused Docker resources..."
docker system prune -af --volumes || true

echo "[cleanup] Removing local demo images if present..."
docker rmi \
  federated-learning-demo-server \
  federated-learning-demo-client-1 \
  federated-learning-demo-client-2 \
  federated-learning-demo-client-3 \
  federated-learning-demo-dashboard 2>/dev/null || true

echo "[cleanup] Done."
