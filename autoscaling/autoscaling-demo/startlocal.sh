#!/bin/bash

echo "Starting Autoscaling Demo Locally..."

# Function to check if a port is available
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null ; then
        echo "Port $port is already in use"
        return 1
    else
        echo "Port $port is available"
        return 0
    fi
}

# Function to find an available port
find_available_port() {
    local start_port=$1
    local port=$start_port
    while ! check_port $port; do
        port=$((port + 1))
        if [ $port -gt $((start_port + 100)) ]; then
            echo "Could not find available port starting from $start_port"
            exit 1
        fi
    done
    echo $port
}

# Check and install dependencies
echo "Checking dependencies..."
if ! command -v python3 &> /dev/null; then
    echo "Python3 is not installed"
    exit 1
fi

if ! command -v pip3 &> /dev/null; then
    echo "pip3 is not installed"
    exit 1
fi

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install -r requirements.txt

# Start Redis if not running
echo "Starting Redis..."
if ! brew services list | grep -q "redis.*started"; then
    brew services start redis
    sleep 3
fi

# Check if Redis is running
echo "Checking Redis connection..."
if redis-cli ping > /dev/null 2>&1; then
    echo "Redis is running"
else
    echo "Redis failed to start"
    exit 1
fi

# Find available port (start with 3000, fallback to others)
echo "Finding available port..."
PORT=$(find_available_port 3000)
echo "Using port $PORT"

# Update the Flask app to use the available port
echo "Configuring Flask app..."
sed -i.bak "s/port=3000/port=$PORT/g" src/main.py

# Create a simple startup script for the Flask app
cat > start_flask.py << EOF
#!/usr/bin/env python3
import sys
import os

# Add src to Python path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), 'src'))

# Import and run the main app
from main import app, socketio, engine
import threading

if __name__ == '__main__':
    # Start the engine automatically
    threading.Thread(target=engine.start, daemon=True).start()
    socketio.run(app, host='0.0.0.0', port=${PORT}, debug=False, allow_unsafe_werkzeug=True)
EOF

# Start the Flask application
echo "Starting Flask application on port $PORT..."
python3 start_flask.py &
FLASK_PID=$!

# Wait for the app to start
echo "Waiting for application to start..."
sleep 5

# Check if the app is running
if curl -s http://localhost:$PORT/api/status > /dev/null; then
    echo ""
    echo "Autoscaling Demo is running successfully!"
    echo ""
    echo "Web Interface: http://localhost:$PORT"
    echo "API Status: http://localhost:$PORT/api/status"
    echo ""
    echo "Features:"
    echo "   • Real-time autoscaling metrics"
    echo "   • Three autoscaling algorithms (Reactive, Predictive, Hybrid)"
    echo "   • Load simulation with different patterns"
    echo "   • WebSocket-based real-time updates"
    echo ""
    echo "To stop: ./stoplocal.sh"
    echo "Logs: tail -f logs/app.log"
    echo ""
    echo "Press Ctrl+C to stop the demo"
    
    # Save PID for easy stopping
    echo $FLASK_PID > .flask_pid
    echo $PORT > .flask_port
    
    # Wait for user to stop
    wait $FLASK_PID
else
    echo "Failed to start the application"
    echo "Check the logs above for errors"
    kill $FLASK_PID 2>/dev/null
    exit 1
fi 