#!/bin/bash

echo "🚀 Starting Event Sourcing & CQRS Demo..."
echo ""

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose not found. Please install Docker Compose."
    exit 1
fi

# Check if Docker is running
if ! docker info &> /dev/null; then
    echo "❌ Docker is not running. Please start Docker."
    exit 1
fi

# Build containers if needed (or if images don't exist)
echo "📦 Building/checking Docker containers..."
docker-compose build --quiet

# Start services
echo ""
echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo ""
echo "⏳ Waiting for services to be ready..."
sleep 5

# Check service health
echo ""
echo "🔍 Checking service health..."

MAX_RETRIES=30
RETRY_COUNT=0

check_service() {
    local service=$1
    local port=$2
    local url=$3
    
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -s -f "$url" > /dev/null 2>&1; then
            echo "  ✅ $service is ready"
            return 0
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 1
    done
    echo "  ⚠️  $service may not be ready yet (check logs with: docker-compose logs $service)"
    return 1
}

check_postgres() {
    local service="PostgreSQL"
    local container="postgres"
    
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if docker-compose exec -T "$container" pg_isready -U postgres > /dev/null 2>&1; then
            echo "  ✅ $service is ready"
            return 0
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 1
    done
    echo "  ⚠️  $service may not be ready yet (check logs with: docker-compose logs $container)"
    return 1
}

check_redis() {
    local service="Redis"
    local container="redis"
    
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if docker-compose exec -T "$container" redis-cli ping > /dev/null 2>&1; then
            echo "  ✅ $service is ready"
            return 0
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        sleep 1
    done
    echo "  ⚠️  $service may not be ready yet (check logs with: docker-compose logs $container)"
    return 1
}

# Check services
check_postgres || true
check_redis || true
check_service "Event Store" "3001" "http://localhost:3001/health" || true
check_service "Command Service" "3002" "http://localhost:3002/health" || true
check_service "Query Service" "3003" "http://localhost:3003/health" || true
check_service "Projection Service" "3004" "http://localhost:3004/health" || true

# Dashboard takes longer to start (Vite dev server)
echo "  ⏳ Dashboard is starting (may take 30-60 seconds)..."
sleep 10

echo ""
echo "✅ Services started!"
echo ""
echo "🌐 Dashboard: http://localhost:3000"
echo ""
echo "📊 Service URLs:"
echo "   Command Service:    http://localhost:3002"
echo "   Query Service:      http://localhost:3003"
echo "   Event Store:        http://localhost:3001"
echo "   Projection Stats:   http://localhost:3004/stats"
echo ""
echo "📝 Useful commands:"
echo "   View logs:          docker-compose logs -f"
echo "   Stop services:     docker-compose down"
echo "   Generate demo data: ./demo-data.sh"
echo "   Run tests:          ./tests/integration.test.sh"
echo ""



