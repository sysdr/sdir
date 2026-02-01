#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "🚀 Starting RTB services from $SCRIPT_DIR..."
docker-compose up -d
echo "⏳ Waiting for services..."
sleep 6
echo "✅ Services started. Dashboard: http://localhost:3000"
