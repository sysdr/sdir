#!/bin/bash
# Comprehensive cleanup script for microservice architectures
# Stops containers and removes unused Docker resources

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR" || exit 1

echo "=== Cleaning Up Microservice Decomposition Strategies ==="
echo ""

# Stop and remove Docker containers
if command -v docker-compose &> /dev/null && [ -f docker-compose.yml ]; then
    echo "Stopping Docker containers..."
    docker-compose down -v 2>/dev/null || true
    echo "✅ Docker containers stopped and removed"
elif command -v docker &> /dev/null && [ -f docker-compose.yml ]; then
    echo "Stopping Docker containers (using docker compose)..."
    docker compose down -v 2>/dev/null || true
    echo "✅ Docker containers stopped and removed"
fi

# Stop any running containers
if command -v docker &> /dev/null; then
    echo "Stopping any running containers..."
    docker ps -q | xargs -r docker stop 2>/dev/null || true
    
    # Remove stopped containers from this project
    echo "Removing stopped containers..."
    docker ps -a --filter "name=microservice_decomposition" -q | xargs -r docker rm -f 2>/dev/null || true
    
    # Remove unused Docker resources
    echo "Removing unused Docker resources..."
    docker system prune -f 2>/dev/null || true
    
    # Remove unused images
    echo "Removing unused Docker images..."
    docker image prune -f 2>/dev/null || true
    
    # Remove unused volumes
    echo "Removing unused Docker volumes..."
    docker volume prune -f 2>/dev/null || true
    
    # Remove unused networks
    echo "Removing unused Docker networks..."
    docker network prune -f 2>/dev/null || true
fi

# Stop HTTP server if PID file exists
if [ -f .http_pid ]; then
    HTTP_PID=$(cat .http_pid 2>/dev/null)
    if [ -n "$HTTP_PID" ] && kill -0 "$HTTP_PID" 2>/dev/null; then
        echo "Stopping HTTP server (PID: $HTTP_PID)..."
        kill "$HTTP_PID" 2>/dev/null || true
        echo "✅ HTTP server stopped"
    fi
    rm -f .http_pid
fi

# Kill any processes on the ports (fallback)
for port in 3001 3002 3003 3004 3005 3006 3007 8080; do
    PID=$(lsof -ti:$port 2>/dev/null)
    if [ -n "$PID" ]; then
        echo "Killing process on port $port (PID: $PID)..."
        kill "$PID" 2>/dev/null || true
    fi
done

# Stop services by PID files
for pidfile in .*.pid; do
    if [ -f "$pidfile" ]; then
        PID=$(cat "$pidfile" 2>/dev/null)
        SERVICE_NAME=$(echo "$pidfile" | sed 's/^\.//' | sed 's/\.pid$//')
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo "Stopping $SERVICE_NAME (PID: $PID)..."
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$pidfile"
    fi
done

# Clean up PID and log files
echo "Cleaning up PID and log files..."
rm -f .*.pid .*.log .http_pid 2>/dev/null || true

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Note: This script removes Docker containers, images, volumes, and networks."
echo "To remove all unused Docker resources system-wide, run: docker system prune -a"
