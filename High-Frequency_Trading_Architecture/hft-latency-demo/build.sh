#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"
echo "📦 Building HFT Latency Demo containers in $SCRIPT_DIR..."
docker-compose build
echo "✅ Build complete."
