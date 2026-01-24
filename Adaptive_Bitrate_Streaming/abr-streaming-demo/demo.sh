#!/bin/bash

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🎬 Starting ABR Streaming Demo..."
echo ""
echo "📺 Frontend: http://localhost:3000"
echo "🔌 Backend API: http://localhost:4000"
echo "📊 Metrics: http://localhost:4000/metrics"
echo ""
echo "Press Ctrl+C to stop"

docker-compose up
