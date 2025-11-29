#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🚀 Starting GraphQL Federation Services"
echo "========================================"

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 ; then
        return 0
    else
        return 1
    fi
}

# Function to kill process on a port
kill_port() {
    local port=$1
    local pid=$(lsof -ti:$port 2>/dev/null)
    if [ ! -z "$pid" ]; then
        echo "⚠️  Killing process on port $port (PID: $pid)"
        kill -9 $pid 2>/dev/null || true
        sleep 1
    fi
}

# Check and kill any existing services
echo "🔍 Checking for existing services..."
for port in 4001 4002 4003 4000 3000; do
    if check_port $port; then
        echo "⚠️  Port $port is already in use"
        kill_port $port
    fi
done

# Install dependencies for each service
echo ""
echo "📦 Installing dependencies..."
cd "$SCRIPT_DIR/users-service"
if [ ! -d "node_modules" ]; then
    echo "  Installing users-service dependencies..."
    npm install
fi

cd "$SCRIPT_DIR/products-service"
if [ ! -d "node_modules" ]; then
    echo "  Installing products-service dependencies..."
    npm install
fi

cd "$SCRIPT_DIR/reviews-service"
if [ ! -d "node_modules" ]; then
    echo "  Installing reviews-service dependencies..."
    npm install
fi

cd "$SCRIPT_DIR/gateway"
if [ ! -d "node_modules" ]; then
    echo "  Installing gateway dependencies..."
    npm install
fi

cd "$SCRIPT_DIR/dashboard"
if [ ! -d "node_modules" ]; then
    echo "  Installing dashboard dependencies..."
    npm install
fi

# Start services in background
echo ""
echo "🚀 Starting services..."

cd "$SCRIPT_DIR/users-service"
node server.js > ../logs/users-service.log 2>&1 &
USERS_PID=$!
echo "  ✅ Users Service started (PID: $USERS_PID) on port 4001"

cd "$SCRIPT_DIR/products-service"
node server.js > ../logs/products-service.log 2>&1 &
PRODUCTS_PID=$!
echo "  ✅ Products Service started (PID: $PRODUCTS_PID) on port 4002"

cd "$SCRIPT_DIR/reviews-service"
node server.js > ../logs/reviews-service.log 2>&1 &
REVIEWS_PID=$!
echo "  ✅ Reviews Service started (PID: $REVIEWS_PID) on port 4003"

# Wait for services to be ready
echo ""
echo "⏳ Waiting for services to be ready..."
sleep 5

cd "$SCRIPT_DIR/gateway"
node server.js > ../logs/gateway.log 2>&1 &
GATEWAY_PID=$!
echo "  ✅ Gateway started (PID: $GATEWAY_PID) on port 4000"

# Wait for gateway to be ready
sleep 5

cd "$SCRIPT_DIR/dashboard"
node server.js > ../logs/dashboard.log 2>&1 &
DASHBOARD_PID=$!
echo "  ✅ Dashboard started (PID: $DASHBOARD_PID) on port 3000"

# Create PID file
mkdir -p "$SCRIPT_DIR/logs"
echo "$USERS_PID" > "$SCRIPT_DIR/logs/users-service.pid"
echo "$PRODUCTS_PID" > "$SCRIPT_DIR/logs/products-service.pid"
echo "$REVIEWS_PID" > "$SCRIPT_DIR/logs/reviews-service.pid"
echo "$GATEWAY_PID" > "$SCRIPT_DIR/logs/gateway.pid"
echo "$DASHBOARD_PID" > "$SCRIPT_DIR/logs/dashboard.pid"

echo ""
echo "✅ All services started!"
echo "================================"
echo "📊 Dashboard: http://localhost:3000"
echo "🚪 Gateway: http://localhost:4000/graphql"
echo "👤 Users Service: http://localhost:4001/graphql"
echo "📦 Products Service: http://localhost:4002/graphql"
echo "⭐ Reviews Service: http://localhost:4003/graphql"
echo ""
echo "📝 Logs are in: $SCRIPT_DIR/logs/"
echo ""
echo "To stop services, run: ./stop-services.sh"

