#!/bin/bash

echo "🚀 Starting Database Scaling Demo..."
echo "==================================="

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if docker-compose is available
if ! command -v docker-compose &> /dev/null; then
    echo "❌ docker-compose is not installed. Please install it and try again."
    exit 1
fi

# Build and start the demo
echo "🔨 Building and starting the demo..."
docker-compose up --build -d

echo ""
echo "🎉 Demo is starting up!"
echo "🌐 Access the demo at: http://localhost:8000"
echo "📊 Monitor the logs with: docker-compose logs -f"
echo "🛑 Stop the demo with: docker-compose down"
echo ""
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check if the app is responding
echo "🔍 Checking if the demo is ready..."
if curl -s http://localhost:8000 > /dev/null; then
    echo "✅ Demo is ready! Visit http://localhost:8000"
else
    echo "⏳ Demo is still starting up. Please wait a moment and try again."
    echo "📊 You can monitor the startup with: docker-compose logs -f"
fi 