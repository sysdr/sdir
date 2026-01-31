#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" && docker-compose up -d
echo "Services started. Dashboard: http://localhost:8080"
