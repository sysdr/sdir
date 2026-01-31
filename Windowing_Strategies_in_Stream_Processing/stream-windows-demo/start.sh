#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1
echo "Starting Windowing Strategies Demo from $SCRIPT_DIR..."
docker-compose up -d
echo "Dashboard: http://localhost:3000 | Backend: http://localhost:3001"
