#!/bin/bash
# Cleanup script for autoscaling demo

echo "🧹 Cleaning up Autoscaling Demo..."

# Stop Docker containers
echo "📦 Stopping Docker containers..."
docker-compose down -v 2>/dev/null || true

# Remove Docker images
echo "🗑️ Removing Docker images..."
docker rmi autoscaling-demo_autoscaler 2>/dev/null || true

# Kill all Python processes related to the demo
echo "🐍 Stopping Python processes..."
pkill -f "python.*main.py" 2>/dev/null || true
pkill -f "python.*test_flask.py" 2>/dev/null || true
pkill -f "python.*start_flask.py" 2>/dev/null || true

# Kill any Flask processes
echo "🔥 Stopping Flask processes..."
pkill -f "flask" 2>/dev/null || true

# Stop Redis service if running
echo "🔴 Stopping Redis service..."
brew services stop redis 2>/dev/null || true
sudo systemctl stop redis 2>/dev/null || true

# Clean up temporary files
echo "🗂️ Cleaning up temporary files..."
rm -f start_flask.py 2>/dev/null || true
rm -f .flask_pid 2>/dev/null || true
rm -f .flask_port 2>/dev/null || true
rm -f *.pyc 2>/dev/null || true
rm -rf __pycache__ 2>/dev/null || true
rm -rf src/__pycache__ 2>/dev/null || true

# Clean up logs
echo "📝 Cleaning up logs..."
rm -rf logs/* 2>/dev/null || true

# Clean up data
echo "💾 Cleaning up data..."
rm -rf data/* 2>/dev/null || true

# Check for any remaining processes on ports
echo "🔍 Checking for processes on demo ports..."
lsof -ti:3000 | xargs kill -9 2>/dev/null || true
lsof -ti:5000 | xargs kill -9 2>/dev/null || true
lsof -ti:8080 | xargs kill -9 2>/dev/null || true
lsof -ti:6379 | xargs kill -9 2>/dev/null || true

echo "✅ Cleanup complete!"
echo ""
echo "🎯 All autoscaling demo processes stopped and cleaned up!"
echo "📊 Ports 3000, 5000, 8080, and 6379 are now available"
