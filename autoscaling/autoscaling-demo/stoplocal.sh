#!/bin/bash

echo "🛑 Stopping Autoscaling Demo..."

# Stop Flask application
if [ -f .flask_pid ]; then
    FLASK_PID=$(cat .flask_pid)
    if ps -p $FLASK_PID > /dev/null; then
        echo "🔄 Stopping Flask application (PID: $FLASK_PID)..."
        kill $FLASK_PID
        sleep 2
        
        # Force kill if still running
        if ps -p $FLASK_PID > /dev/null; then
            echo "🔨 Force killing Flask application..."
            kill -9 $FLASK_PID
        fi
    else
        echo "ℹ️  Flask application already stopped"
    fi
    rm -f .flask_pid
else
    echo "ℹ️  No Flask PID file found"
fi

# Kill any remaining Python processes related to the demo
echo "🧹 Cleaning up Python processes..."
pkill -f "start_flask.py" 2>/dev/null
pkill -f "main.py" 2>/dev/null

# Remove temporary files
echo "🧹 Cleaning up temporary files..."
rm -f start_flask.py
rm -f .flask_port
rm -f src/main.py.bak

# Check if Redis should be stopped (only if we started it)
if [ -f .redis_started ]; then
    echo "🔴 Stopping Redis..."
    brew services stop redis
    rm -f .redis_started
else
    echo "ℹ️  Redis was already running, leaving it active"
fi

# Check if ports are free
if [ -f .flask_port ]; then
    PORT=$(cat .flask_port)
    if lsof -Pi :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo "⚠️  Port $PORT is still in use by another process"
    else
        echo "✅ Port $PORT is now free"
    fi
    rm -f .flask_port
fi

echo "✅ Autoscaling Demo stopped successfully!"
echo ""
echo "💡 To start again: ./startlocal.sh"
