#!/bin/bash

# Distributed Task Scheduler - Start Script
# This script starts the entire distributed scheduler system

set -e

echo "🚀 Starting Distributed Task Scheduler..."

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

# Create logs directory if it doesn't exist
mkdir -p logs

# Create static and templates directories if they don't exist
mkdir -p static templates

# Start the services
echo "📦 Starting services with Docker Compose..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check if services are running
echo "🔍 Checking service status..."
docker-compose ps

# Get service URLs
echo ""
echo "✅ Distributed Task Scheduler is running!"
echo ""
echo "🌐 Service URLs:"
echo "   • Web Dashboard: http://localhost:3000"
echo "   • Scheduler API: http://localhost:8000"
echo "   • Worker 1 API: http://localhost:8001"
echo "   • Worker 2 API: http://localhost:8002"
echo "   • Worker 3 API: http://localhost:8003"
echo "   • Redis: localhost:6379"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "📋 API Documentation: http://localhost:8000/docs"
echo ""
echo "To stop the system, run: ./stop.sh"
echo "To view logs, run: docker-compose logs -f" 