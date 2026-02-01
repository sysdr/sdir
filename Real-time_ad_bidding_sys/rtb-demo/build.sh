#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
echo "🏗️  Building RTB Docker images in $SCRIPT_DIR..."
docker-compose build
echo "✅ Build complete."
