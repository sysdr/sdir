#!/bin/bash

echo "🧹 Cleaning up Multi-Region Architecture Demo..."

# Stop the application
if [ -f .demo_pid ]; then
    PID=$(cat .demo_pid)
    if ps -p $PID > /dev/null; then
        echo "🛑 Stopping application (PID: $PID)..."
        kill $PID
        sleep 2
        
        # Force kill if still running
        if ps -p $PID > /dev/null; then
            echo "🔥 Force stopping application..."
            kill -9 $PID
        fi
    fi
    rm -f .demo_pid
fi

# Stop any Python processes running the demo
echo "🔍 Stopping any remaining demo processes..."
pkill -f "python app/main.py" 2>/dev/null || true
pkill -f "multi-region-demo" 2>/dev/null || true

# Stop Docker containers
echo "🐳 Stopping Docker containers..."
docker-compose down 2>/dev/null || true

# Remove Docker images
echo "🗑️ Removing Docker images..."
docker rmi multi-region-demo 2>/dev/null || true

# Remove Docker volumes
echo "📦 Cleaning up Docker volumes..."
docker volume prune -f 2>/dev/null || true



# Clean up any temporary files
echo "🧽 Cleaning temporary files..."
rm -f *.log *.pid 2>/dev/null || true

# Stop any Redis containers that might be running
echo "🔴 Stopping Redis containers..."
docker stop $(docker ps -q --filter "ancestor=redis:7-alpine") 2>/dev/null || true

# Clean up Python cache
echo "🐍 Cleaning Python cache..."
find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find . -type f -name "*.pyc" -delete 2>/dev/null || true

# Kill any processes using port 5000
echo "🔌 Freeing up port 5000..."
lsof -ti:5000 | xargs kill -9 2>/dev/null || true

echo "✅ Cleanup completed!"
echo "🎯 All demo components have been stopped and removed."
echo "💾 Your system is now clean and ready for the next demo."