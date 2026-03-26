#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
docker compose down --remove-orphans 2>/dev/null || true
docker compose up -d --build
echo "Services starting. Dashboard: http://localhost:3000"
