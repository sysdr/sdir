#!/bin/bash

echo "🚀 Starting Bulkheads and Isolation Demo..."

# Function to check if service is ready
wait_for_service() {
    echo "⏳ Waiting for service to be ready..."
    for i in {1..30}; do
        if curl -s http://localhost:5000/ > /dev/null 2>&1; then
            echo "✅ Service is ready!"
            return 0
        fi
        echo "Waiting... ($i/30)"
        sleep 2
    done
    echo "❌ Service failed to start within timeout"
    return 1
}

# Check if running with Docker
if [ "$1" = "--docker" ]; then
    echo "🐳 Starting with Docker Compose..."
    docker-compose down --remove-orphans 2>/dev/null
    docker-compose build
    docker-compose up -d
    
    if wait_for_service; then
        echo "🧪 Running tests..."
        python3 test_demo.py
    fi
else
    echo "💻 Starting with Python directly..."
    
    # Install dependencies
    if [ ! -d "venv" ]; then
        echo "📦 Creating virtual environment..."
        python3 -m venv venv
    fi
    
    source venv/bin/activate
    pip install -r requirements.txt
    
    # Start the application in background
    echo "🔧 Starting application..."
    python3 src/app.py &
    APP_PID=$!
    
    # Wait for service and run tests
    if wait_for_service; then
        echo "🧪 Running tests..."
        python3 test_demo.py
    fi
    
    # Cleanup
    echo "🛑 Stopping application..."
    kill $APP_PID 2>/dev/null
fi

echo ""
echo "🎯 Demo completed!"
echo "📊 Access the demo at: http://localhost:5000"
echo "📚 Features demonstrated:"
echo "   • Isolated thread pools per service"
echo "   • Connection pool isolation"
echo "   • Failure rate injection"
echo "   • Real-time monitoring"
echo "   • Bulkhead effectiveness visualization"
