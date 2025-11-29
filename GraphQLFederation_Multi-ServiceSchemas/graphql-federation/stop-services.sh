#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🛑 Stopping GraphQL Federation Services"
echo "========================================"

# Function to kill process from PID file
kill_service() {
    local service=$1
    local pid_file="$SCRIPT_DIR/logs/$service.pid"
    
    if [ -f "$pid_file" ]; then
        local pid=$(cat "$pid_file")
        if ps -p $pid > /dev/null 2>&1; then
            echo "  Stopping $service (PID: $pid)..."
            kill $pid 2>/dev/null || true
            sleep 1
            # Force kill if still running
            if ps -p $pid > /dev/null 2>&1; then
                kill -9 $pid 2>/dev/null || true
            fi
            rm -f "$pid_file"
            echo "  ✅ $service stopped"
        else
            echo "  ⚠️  $service not running (PID: $pid)"
            rm -f "$pid_file"
        fi
    else
        echo "  ⚠️  No PID file found for $service"
    fi
}

# Kill services
kill_service "dashboard"
kill_service "gateway"
kill_service "reviews-service"
kill_service "products-service"
kill_service "users-service"

# Also kill any processes on the ports
echo ""
echo "🔍 Checking for processes on service ports..."
for port in 3000 4000 4001 4002 4003; do
    pid=$(lsof -ti:$port 2>/dev/null)
    if [ ! -z "$pid" ]; then
        echo "  Killing process on port $port (PID: $pid)"
        kill -9 $pid 2>/dev/null || true
    fi
done

echo ""
echo "✅ All services stopped!"

