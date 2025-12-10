#!/bin/bash
set -e

echo "🎬 Starting Buffer Bloat Demonstration..."
echo "========================================"
echo ""

# Build Docker image
echo "📦 Building Docker image..."
docker-compose build

# Start container
echo "🚀 Starting demonstration..."
docker-compose up -d

# Wait for container to be ready
sleep 3

# Setup network inside container
echo "🌐 Configuring network namespaces..."
docker exec bufferbloat-demo /app/setup_network.sh

# Start traffic generation in background
echo "🚥 Generating background traffic..."
docker exec -d bufferbloat-demo /app/generate_traffic.sh

# Run tests (optional - skip if tests directory not available)
echo "🧪 Running tests..."
if docker exec bufferbloat-demo test -f /app/../tests/test_bufferbloat.py 2>/dev/null; then
    docker exec bufferbloat-demo python /app/../tests/test_bufferbloat.py
else
    echo "⚠️  Tests skipped (test file not found in container)"
fi

echo ""
echo "✅ Demo is running!"
echo "========================================"
echo ""
echo "📊 Open your browser to: http://localhost:5000"
echo ""
echo "You should see:"
echo "  • Normal Queue: ~20-30ms latency (healthy)"
echo "  • Buffer Bloat: ~200-500ms+ latency (degraded)"
echo "  • AQM: ~25-40ms latency (optimal)"
echo ""
echo "💡 The dashboard updates in real-time showing how excessive"
echo "   buffering causes high latency even with zero packet loss."
echo ""
echo "🛑 To stop: bash cleanup.sh"
