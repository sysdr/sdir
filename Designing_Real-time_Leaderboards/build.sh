#!/bin/bash

set -e

echo "========================================="
echo "Building Real-Time Leaderboard Demo"
echo "========================================="

# Check if leaderboard-demo directory exists
if [ ! -d "leaderboard-demo" ]; then
    echo "Error: leaderboard-demo directory not found!"
    echo "Please run setup.sh first to generate the demo files."
    exit 1
fi

cd leaderboard-demo

# Check if docker-compose.yml exists
if [ ! -f "docker-compose.yml" ]; then
    echo "Error: docker-compose.yml not found!"
    echo "Please run setup.sh first to generate the demo files."
    exit 1
fi

# Check for running containers and stop them if needed
echo ""
echo "Checking for running containers..."
if docker-compose ps | grep -q "Up"; then
    echo "Stopping existing containers..."
    docker-compose down
fi

# Build Docker containers
echo ""
echo "Building Docker containers..."
docker-compose build --no-cache

# Start services
echo ""
echo "Starting services..."
docker-compose up -d

# Wait for services to be healthy
echo ""
echo "Waiting for services to be healthy..."
sleep 10

# Check service status
echo ""
echo "Service Status:"
docker-compose ps

# Display access information
echo ""
echo "========================================="
echo "✓ Build Complete!"
echo "========================================="
echo ""
echo "📊 Dashboard: http://localhost:8080"
echo "🔌 API: http://localhost:3000"
echo "📈 Stats: http://localhost:3000/stats"
echo ""
echo "🔧 View logs: docker-compose logs -f"
echo "🧹 Stop services: docker-compose down"
echo ""
echo "========================================="

