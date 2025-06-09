#!/bin/bash

echo "🔧 Setting up Consistent Hashing Demo..."

# Check if Docker is available
if command -v docker &> /dev/null; then
    echo "🐳 Docker detected. Building and running with Docker..."
    
    # Build and run with Docker Compose
    docker-compose down 2>/dev/null || true
    docker-compose up --build -d
    
    echo "⏳ Waiting for services to start..."
    sleep 10
    
    echo "✅ Demo is running!"
    echo "🌐 Web Interface: http://localhost:5000"
    echo "📊 Redis: localhost:6379"
    echo ""
    echo "To stop: docker-compose down"
    
else
    echo "🐍 Docker not found. Running with local Python..."
    
    # Install dependencies
    pip install -r requirements.txt
    
    # Start Redis if available
    if command -v redis-server &> /dev/null; then
        echo "🔴 Starting Redis server..."
        redis-server --daemonize yes --port 6379
    fi
    
    # Run the application
    cd src && python app.py
fi
