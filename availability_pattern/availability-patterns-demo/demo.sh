#!/bin/bash

echo "🚀 Starting Availability Patterns Demo..."

# Check dependencies
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed."; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed."; exit 1; }
command -v curl >/dev/null 2>&1 || { echo "❌ curl is required but not installed."; exit 1; }

# Clean up any existing containers
echo "🧹 Cleaning up existing containers..."
docker-compose down --remove-orphans 2>/dev/null || true

# Install Node.js dependencies
echo "📦 Installing dependencies..."
npm install

# Build and start containers
echo "🏗️ Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

# Wait for services to be ready with better feedback
echo "⏳ Waiting for services to be ready..."
echo "   This may take up to 60 seconds for all services to start..."

# Wait for Redis to be healthy first
echo "   Waiting for Redis to be healthy..."
for i in {1..30}; do
    if docker-compose ps redis | grep -q "healthy"; then
        echo "   ✅ Redis is healthy"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "   ❌ Redis failed to become healthy"
        docker-compose logs redis
        exit 1
    fi
    sleep 2
done

# Wait for application containers to start
echo "   Waiting for application containers to start..."
for i in {1..30}; do
    running_count=$(docker-compose ps | grep -E "(ap-primary|ap-standby|aa-node1|aa-node2)" | grep -c "Up" || echo "0")
    if [ "$running_count" -eq 4 ]; then
        echo "   ✅ All application containers are running"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "   ❌ Some application containers failed to start"
        docker-compose ps
        exit 1
    fi
    sleep 2
done

# Additional wait for services to fully initialize
echo "   Waiting for services to fully initialize..."
sleep 10

# Run health checks with retries
echo "🩺 Running health checks..."
for port in 3001 3002 3003 3004; do
    echo "   Checking service on port $port..."
    for attempt in {1..5}; do
        if curl -f -s http://localhost:$port/health >/dev/null 2>&1; then
            echo "   ✅ Service on port $port is healthy"
            break
        else
            if [ $attempt -eq 5 ]; then
                echo "   ❌ Service on port $port is not responding after 5 attempts"
                echo "   Checking container logs..."
                case $port in
                    3001) docker-compose logs app-ap-primary --tail=10 ;;
                    3002) docker-compose logs app-ap-standby --tail=10 ;;
                    3003) docker-compose logs app-aa-node1 --tail=10 ;;
                    3004) docker-compose logs app-aa-node2 --tail=10 ;;
                esac
            else
                echo "   ⏳ Attempt $attempt/5 - waiting 2 seconds..."
                sleep 2
            fi
        fi
    done
done

# Run tests
echo "🧪 Running tests..."
npm test

echo ""
echo "🎉 Demo is ready!"
echo ""
echo "📊 Dashboard: http://localhost:8000"
echo "🔄 Active-Passive LB: http://localhost:8080"
echo "⚡ Active-Active LB: http://localhost:8081"
echo ""
echo "Individual Services:"
echo "   AP Primary: http://localhost:3001"
echo "   AP Standby: http://localhost:3002"
echo "   AA Node 1:  http://localhost:3003"
echo "   AA Node 2:  http://localhost:3004"
echo ""
echo "🎯 Try these commands:"
echo "   curl http://localhost:8080/api/service  # Active-Passive"
echo "   curl http://localhost:8081/api/service  # Active-Active"
echo ""
echo "💥 Simulate failures:"
echo "   curl -X POST http://localhost:3001/api/simulate-failure"
echo "   curl -X POST http://localhost:3003/api/simulate-failure"
echo ""
echo "📱 Open the dashboard to interact with the demo!"
echo ""
echo "🔧 To stop the demo: docker-compose down"
echo "🔧 To view logs: docker-compose logs -f"
