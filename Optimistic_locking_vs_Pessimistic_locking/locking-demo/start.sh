#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting Optimistic vs Pessimistic Locking Demo..."
echo ""

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found."
    echo "   Please run ../setup.sh first."
    exit 1
fi

# Check for existing/running containers
EXISTING_CONTAINERS=$(docker-compose ps -q 2>/dev/null | wc -l)
if [ "$EXISTING_CONTAINERS" -gt 0 ]; then
    RUNNING=$(docker-compose ps --services --filter "status=running" 2>/dev/null | wc -l)
    if [ "$RUNNING" -gt 0 ]; then
        echo "⚠️  Services are already running."
        echo "   Use 'docker-compose restart' to restart or 'docker-compose down' to stop first."
        echo ""
        docker-compose ps
        exit 0
    fi
fi

# Check for processes using ports 3000, 3001, 5432
PORTS=(3000 3001 5432)
PORTS_IN_USE=()
for port in "${PORTS[@]}"; do
    if (lsof -ti:$port > /dev/null 2>&1) || (command -v ss >/dev/null 2>&1 && ss -tlnp 2>/dev/null | grep -q ":$port "); then
        PORTS_IN_USE+=("$port")
    fi
done

if [ ${#PORTS_IN_USE[@]} -gt 0 ]; then
    echo "⚠️  Warning: Ports in use: ${PORTS_IN_USE[*]}"
    echo "   Attempting to stop existing containers..."
    docker-compose down 2>/dev/null || true
    sleep 3
fi

# Start services
echo "🚀 Starting Docker services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 8

MAX_RETRIES=30
RETRY_COUNT=0
echo -n "   Waiting for backend API"
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -s http://localhost:3001/health > /dev/null 2>&1; then
        echo " ✅"
        break
    fi
    echo -n "."
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 1
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo ""
    echo "⚠️  Warning: Backend not ready after $MAX_RETRIES seconds"
fi

echo ""
echo "📊 Service Status:"
docker-compose ps

echo ""
echo "✅ Services started successfully!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔧 API: http://localhost:3001"
echo ""
echo "Run demo: ./scripts/demo.sh"
echo "Or trigger transactions from the dashboard at http://localhost:3000"
echo ""
