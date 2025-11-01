#!/bin/bash

# IAM Demo Startup Script
# This script starts all services with proper path checking

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=========================================="
echo "IAM Demo - Starting Services"
echo "=========================================="

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found in $SCRIPT_DIR"
    exit 1
fi

# Check if docker is available
if ! command -v docker &> /dev/null; then
    echo "❌ Error: docker command not found"
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null; then
    echo "❌ Error: docker-compose command not found"
    exit 1
fi

# Check for existing containers
echo ""
echo "🔍 Checking for existing containers..."
EXISTING=$(docker ps -a --filter "name=iam-demo" --format "{{.Names}}" 2>/dev/null || true)
if [ ! -z "$EXISTING" ]; then
    echo "⚠️  Found existing containers:"
    echo "$EXISTING"
    echo ""
    read -p "Do you want to stop and remove existing containers? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🛑 Stopping existing containers..."
        docker-compose down 2>/dev/null || docker compose down 2>/dev/null
    else
        echo "ℹ️  Keeping existing containers. Starting services..."
    fi
fi

# Check for duplicate services on ports
echo ""
echo "🔍 Checking for services using ports 3001, 3002, 5432, 6379..."
PORTS_IN_USE=""
for port in 3001 3002 5432 6379; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || netstat -tuln 2>/dev/null | grep -q ":$port " || ss -tuln 2>/dev/null | grep -q ":$port "; then
        PORTS_IN_USE="$PORTS_IN_USE $port"
    fi
done

if [ ! -z "$PORTS_IN_USE" ]; then
    echo "⚠️  Warning: Ports in use: $PORTS_IN_USE"
    echo "   These ports may conflict with IAM demo services"
    echo ""
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Start services
echo ""
echo "🚀 Starting IAM demo services..."
if docker compose version &> /dev/null; then
    docker compose up -d
else
    docker-compose up -d
fi

echo ""
echo "⏳ Waiting for services to be healthy (this may take 30-60 seconds)..."
sleep 5

# Wait for services to be ready
MAX_WAIT=120
WAIT_COUNT=0
while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    HEALTHY=0
    
    # Check auth-server
    if curl -s http://localhost:3001/health >/dev/null 2>&1; then
        HEALTHY=$((HEALTHY + 1))
    fi
    
    # Check resource-server
    if curl -s http://localhost:3002/health >/dev/null 2>&1; then
        HEALTHY=$((HEALTHY + 1))
    fi
    
    if [ $HEALTHY -eq 2 ]; then
        echo "✅ All services are healthy!"
        break
    fi
    
    echo -n "."
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
done

echo ""
echo ""
echo "📊 Service Status:"
docker-compose ps 2>/dev/null || docker compose ps

echo ""
echo "✅ Startup complete!"
echo ""
echo "🔗 Service endpoints:"
echo "  - Auth Server: http://localhost:3001"
echo "  - Resource Server: http://localhost:3002"
echo "  - PostgreSQL: localhost:5432"
echo "  - Redis: localhost:6379"
echo ""
echo "📖 Run './demo.sh' to execute the complete OAuth flow demo"
echo "📊 Run './dashboard.sh' to view metrics and status"

