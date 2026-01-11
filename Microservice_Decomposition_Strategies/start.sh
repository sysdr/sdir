#!/bin/bash
# Startup script to run services locally (without Docker)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "=== Starting Microservice Decomposition Strategies Demo ==="
echo ""

# Check if node is available
if ! command -v node &> /dev/null; then
    echo "❌ Node.js is not installed. Please install Node.js first."
    exit 1
fi

# Function to start a service
start_service() {
    local service_dir=$1
    local port=$2
    local service_name=$3
    
    if [ ! -d "$service_dir" ]; then
        echo "❌ Service directory not found: $service_dir"
        return 1
    fi
    
    if [ ! -f "$service_dir/package.json" ]; then
        echo "❌ package.json not found in: $service_dir"
        return 1
    fi
    
    cd "$service_dir" || return 1
    
    # Install dependencies if node_modules doesn't exist
    if [ ! -d "node_modules" ]; then
        echo "Installing dependencies for $service_name..."
        npm install --silent
    fi
    
    # Check if service is already running
    if lsof -ti:$port > /dev/null 2>&1; then
        echo "⚠️  Port $port is already in use. Skipping $service_name"
        cd "$SCRIPT_DIR" || return 1
        return 0
    fi
    
    echo "Starting $service_name on port $port..."
    node server.js > "../.${service_name}.log" 2>&1 &
    local pid=$!
    echo $pid > "../.${service_name}.pid"
    
    # Wait a moment for service to start
    sleep 2
    
    # Check if process is still running
    if ! kill -0 $pid 2>/dev/null; then
        echo "❌ Failed to start $service_name"
        cd "$SCRIPT_DIR" || return 1
        return 1
    fi
    
    echo "✅ $service_name started (PID: $pid)"
    cd "$SCRIPT_DIR" || return 1
    return 0
}

# Start services
start_service "monolith" 3001 "monolith"
start_service "services/order" 3002 "order-service"
start_service "services/payment" 3003 "payment-service"
start_service "services/inventory" 3004 "inventory-service"
start_service "strangler/gateway" 3005 "strangler-gateway"
start_service "strangler/legacy" 3006 "legacy-monolith"
start_service "strangler/new-services" 3007 "new-payment-service"

# Start HTTP server for dashboard
if [ ! -d "shared" ]; then
    echo "❌ shared directory not found"
    exit 1
fi

if lsof -ti:8080 > /dev/null 2>&1; then
    echo "⚠️  Port 8080 is already in use. Dashboard server may already be running."
else
    echo "Starting dashboard server on port 8080..."
    cd shared || exit 1
    python3 -m http.server 8080 > "../.dashboard.log" 2>&1 &
    DASHBOARD_PID=$!
    echo $DASHBOARD_PID > "../.dashboard.pid"
    cd "$SCRIPT_DIR" || exit 1
    echo "✅ Dashboard server started (PID: $DASHBOARD_PID)"
fi

echo ""
echo "=== All Services Started ==="
echo ""
echo "🎯 Access the dashboard: http://localhost:8080"
echo ""
echo "📊 Architecture endpoints:"
echo "   Monolith:          http://localhost:3001"
echo "   Order Service:     http://localhost:3002"
echo "   Payment Service:   http://localhost:3003"
echo "   Inventory Service: http://localhost:3004"
echo "   Strangler Gateway: http://localhost:3005"
echo "   Legacy Monolith:   http://localhost:3006"
echo "   New Payment:       http://localhost:3007"
echo ""
echo "📝 Logs are in .*.log files"
echo "🛑 Stop services with: bash stop.sh or kill the PIDs in .*.pid files"

