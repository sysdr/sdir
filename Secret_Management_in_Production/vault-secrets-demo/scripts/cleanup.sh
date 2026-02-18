#!/bin/bash
set -e
echo "🧹 Stopping and removing Vault demo containers..."
ROOT="$(cd "$(dirname "$0")"; pwd)"
# When run as DEMO_DIR/cleanup.sh, ROOT is DEMO_DIR; when as DEMO_DIR/scripts/cleanup.sh, go up one
[ -f "$ROOT/docker-compose.yml" ] || ROOT="$(dirname "$ROOT")"
cd "$ROOT"
docker compose down -v --remove-orphans 2>/dev/null || docker-compose down -v --remove-orphans 2>/dev/null || true
docker rmi vault-secrets-demo-backend 2>/dev/null || true
echo "✅ Cleanup complete."
