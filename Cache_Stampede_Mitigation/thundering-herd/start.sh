#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

if [ ! -f "docker-compose.yml" ]; then
    echo "⚠️  docker-compose.yml not found. Run ../setup.sh first."
    exit 1
fi

docker-compose up -d
echo "Dashboard: http://localhost:3000  API: http://localhost:3001"
