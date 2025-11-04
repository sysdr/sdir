#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting Data Pipeline Architecture Demo..."

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found in $(pwd)"
    exit 1
fi

# Check for duplicate services
echo "🔍 Checking for existing services..."
EXISTING_CONTAINERS=$(docker ps -a --filter "name=data-pipeline-demo" --format "{{.Names}}" 2>/dev/null || echo "")
if [ ! -z "$EXISTING_CONTAINERS" ]; then
    echo "⚠️  Found existing containers. Stopping them first..."
    docker-compose down 2>/dev/null || true
fi

# Build and start services
echo "🏗️  Building and starting services..."
docker-compose build
docker-compose up -d

echo "⏳ Waiting for services to start..."
sleep 30

# Check service health
echo "🔍 Checking service health..."
docker-compose ps

echo ""
echo "✅ Data Pipeline Architecture Demo is ready!"
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo ""
echo "📊 Available Patterns:"
echo "  • Stream Processing (Kappa): Real-time event processing"
echo "  • Batch Processing: Historical data analysis"
echo "  • Lambda Architecture: Combined speed + batch layers"
echo ""
echo "🔍 Monitoring:"
echo "  • Real-time metrics in Redis"
echo "  • Historical data in PostgreSQL"
echo "  • Live event stream visualization"
echo ""
echo "🧪 Run tests: cd $(pwd) && ./run-tests.sh"
echo "🛑 Cleanup: cd $(dirname "$SCRIPT_DIR") && ./cleanup.sh"
