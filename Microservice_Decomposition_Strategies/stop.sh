#!/bin/bash
# Stop script to kill all services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "=== Stopping Services ==="
echo ""

# Stop services by PID files
for pidfile in .*.pid; do
    if [ -f "$pidfile" ]; then
        PID=$(cat "$pidfile" 2>/dev/null)
        SERVICE_NAME=$(echo "$pidfile" | sed 's/^\.//' | sed 's/\.pid$//')
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "Stopping $SERVICE_NAME (PID: $PID)..."
            kill "$PID" 2>/dev/null || true
            rm -f "$pidfile"
        fi
    fi
done

# Kill any processes on service ports
for port in 3001 3002 3003 3004 3005 3006 3007 8080; do
    PID=$(lsof -ti:$port 2>/dev/null)
    if [ -n "$PID" ]; then
        echo "Killing process on port $port (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
    fi
done

# Stop Docker containers if docker-compose is available
if command -v docker-compose &> /dev/null && [ -f docker-compose.yml ]; then
    echo "Stopping Docker containers..."
    docker-compose down 2>/dev/null || true
fi

# Clean up PID and log files
rm -f .*.pid .*.log .http_pid

echo ""
echo "✅ All services stopped"

