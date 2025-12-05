#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "======================================"
echo "Starting API Gateway Demo Services"
echo "======================================"
echo ""

# Check if docker-compose is available
DOCKER_COMPOSE_CMD=""
if command -v docker-compose &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    DOCKER_COMPOSE_CMD="docker compose"
elif [ -f "/mnt/c/Program Files/Docker/Docker/resources/bin/docker-compose" ]; then
    export PATH="/mnt/c/Program Files/Docker/Docker/resources/bin:$PATH"
    DOCKER_COMPOSE_CMD="docker-compose"
else
    echo "Error: docker-compose not found"
    echo ""
    echo "Please ensure:"
    echo "  1. Docker Desktop is running"
    echo "  2. WSL integration is enabled in Docker Desktop settings"
    echo "  3. This WSL distribution is enabled in Docker Desktop > Settings > Resources > WSL Integration"
    echo ""
    echo "For details, visit: https://docs.docker.com/go/wsl2/"
    exit 1
fi

# Test docker command
if ! $DOCKER_COMPOSE_CMD version &> /dev/null; then
    echo "Error: Cannot execute docker-compose"
    echo "Please check Docker Desktop WSL integration settings"
    exit 1
fi

# Check for duplicate services
echo "Checking for duplicate services..."
if command -v docker &> /dev/null; then
    EXISTING=$(docker ps --filter "name=api-gateway-demo" -q 2>/dev/null || echo "")
    if [ ! -z "$EXISTING" ]; then
        echo "Warning: Found existing containers. Stopping them..."
        $DOCKER_COMPOSE_CMD down 2>/dev/null || true
        sleep 2
    fi
else
    echo "Warning: Cannot check for existing containers (docker command not available)"
fi

# Check ports
echo "Checking ports..."
PORTS=(3000 3001 3002 3003 3004 3005 6379 8080)
for port in "${PORTS[@]}"; do
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        echo "Warning: Port $port is already in use"
        PID=$(lsof -Pi :$port -sTCP:LISTEN -t)
        echo "  Process using port: $PID"
    fi
done

# Build if needed
echo ""
echo "Building Docker images (if needed)..."
$DOCKER_COMPOSE_CMD build --quiet

# Start services
echo ""
echo "Starting services..."
$DOCKER_COMPOSE_CMD up -d

# Wait for services to be ready
echo ""
echo "Waiting for services to be ready..."
sleep 15

# Health checks
echo ""
echo "Checking service health..."
MAX_RETRIES=30
RETRY_COUNT=0

check_service() {
    local url=$1
    local name=$2
    
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo "✓ $name is healthy"
            return 0
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 1
    done
    
    echo "✗ $name failed to start"
    return 1
}

RETRY_COUNT=0
check_service "http://localhost:3000/health" "Gateway"

RETRY_COUNT=0
check_service "http://localhost:3001/health" "User Service"

RETRY_COUNT=0
check_service "http://localhost:3002/health" "Order Service"

RETRY_COUNT=0
check_service "http://localhost:3003/health" "Analytics Service"

RETRY_COUNT=0
check_service "http://localhost:3004/health" "Notification Service"

# Show running containers
echo ""
echo "Running containers:"
$DOCKER_COMPOSE_CMD ps

echo ""
echo "======================================"
echo "✅ Services started!"
echo "======================================"
echo ""
echo "Access points:"
echo "  • Dashboard: http://localhost:8080"
echo "  • API Gateway: http://localhost:3000"
echo "  • Metrics: http://localhost:3000/metrics"
echo ""


