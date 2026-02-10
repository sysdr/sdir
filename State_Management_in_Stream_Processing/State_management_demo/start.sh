#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "=== Starting State Management Demo ==="
[ ! -f "docker-compose.yml" ] && { echo "Error: Run ./setup.sh first."; exit 1; }
DC_CMD=""; command -v docker-compose &>/dev/null && DC_CMD="docker-compose" || DC_CMD="docker compose"
[ -z "$DC_CMD" ] && { echo "Error: docker-compose not found"; exit 1; }
$DC_CMD ps 2>/dev/null | grep -q "Up" && $DC_CMD up -d || $DC_CMD up -d
sleep 10
echo "Dashboard: http://localhost:3000"; echo "Flink UI: http://localhost:8081"
