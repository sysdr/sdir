#!/bin/bash
set -euo pipefail
DEMO_ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$DEMO_ROOT"

if docker compose version >/dev/null 2>&1; then
  DC="docker compose"
elif docker-compose version >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo "Docker Compose not found." >&2
  exit 1
fi

echo "[start] Demo root: $DEMO_ROOT"
if $DC ps -q 2>/dev/null | grep -q .; then
  echo "[start] Compose project already has containers (docker compose ps). If ports conflict, run ./cleanup.sh first."
fi

log_build() { echo "[start] $*"; }
log_build "Building images (npm install on first dashboard build may take ~2 min)..."
$DC build

log_build "Starting services..."
$DC up -d

log_build "Waiting for API health..."
for i in $(seq 1 40); do
  if curl -sf http://localhost:8000/health >/dev/null 2>&1; then
    echo "[start] Server healthy."
    exit 0
  fi
  sleep 3
  [ "$i" -eq 40 ] && { echo "[start] Server failed health check." >&2; exit 1; }
done
