#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
if [ ! -d "thundering-herd" ]; then
    echo "⚠️  thundering-herd not found. Run ./setup.sh or ./build.sh first."
    exit 1
fi
(cd thundering-herd && docker-compose up -d)
echo "Dashboard: http://localhost:3000  API: http://localhost:3001"
