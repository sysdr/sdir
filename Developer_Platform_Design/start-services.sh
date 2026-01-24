#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV_PLATFORM_DIR="${SCRIPT_DIR}/dev-platform"

echo "======================================"
echo "Starting Developer Platform Services"
echo "======================================"

# Check if dev-platform directory exists
if [ ! -d "$DEV_PLATFORM_DIR" ]; then
    echo "❌ Error: dev-platform directory not found!"
    echo "Please run setup.sh first."
    exit 1
fi

# Check if docker-compose.yml exists
if [ ! -f "${DEV_PLATFORM_DIR}/docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found!"
    echo "Please run setup.sh first."
    exit 1
fi

# Check for duplicate services
echo ""
echo "Checking for existing services..."
EXISTING_SERVICES=$(docker ps --filter "name=catalog\|deployer\|metrics\|portal" --format "{{.Names}}" 2>/dev/null || true)
if [ -n "$EXISTING_SERVICES" ]; then
    echo "⚠️  Warning: Found existing services:"
    echo "$EXISTING_SERVICES"
    echo ""
    read -p "Do you want to stop existing services and restart? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "Stopping existing services..."
        cd "$DEV_PLATFORM_DIR"
        docker-compose down 2>/dev/null || true
    else
        echo "Keeping existing services. Exiting."
        exit 0
    fi
fi

# Change to dev-platform directory
cd "$DEV_PLATFORM_DIR"

# Build and start services
echo ""
echo "Building Docker containers..."
docker-compose build

echo ""
echo "Starting services..."
docker-compose up -d

echo ""
echo "Waiting for services to initialize..."
sleep 15

# Check service health
echo ""
echo "Checking service health..."
SERVICES=("catalog:3001" "deployer:3002" "metrics:3003")
ALL_HEALTHY=true

for service in "${SERVICES[@]}"; do
    name="${service%%:*}"
    port="${service##*:}"
    if curl -s -f "http://localhost:${port}/health" > /dev/null 2>&1; then
        echo "✅ ${name} is healthy"
    else
        echo "❌ ${name} is not responding"
        ALL_HEALTHY=false
    fi
done

if [ "$ALL_HEALTHY" = true ]; then
    echo ""
    echo "======================================"
    echo "✅ All services started successfully!"
    echo "======================================"
    echo ""
    echo "🌐 Developer Portal: http://localhost:3000"
    echo "📚 Service Catalog API: http://localhost:3001"
    echo "🚀 Deployment API: http://localhost:3002"
    echo "📊 Metrics API: http://localhost:3003"
    echo ""
    echo "To view logs: docker-compose logs -f"
    echo "To stop: docker-compose down"
else
    echo ""
    echo "⚠️  Some services are not healthy. Check logs with: docker-compose logs"
    exit 1
fi

