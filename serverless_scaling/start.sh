#!/bin/bash

# Serverless Scaling Demo - Start Script
# System Design Interview Roadmap - Issue #101

set -e

echo "🚀 Starting Serverless Scaling Demo..."
echo "======================================"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]] || [[ ! -d "src" ]]; then
    echo "❌ This doesn't appear to be the serverless scaling demo directory."
    echo "Please run this script from the demo directory."
    exit 1
fi

# Check if services are already running
if docker-compose ps | grep -q "Up"; then
    echo "⚠️  Some services are already running."
    read -p "Do you want to restart all services? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔄 Restarting services..."
        docker-compose down
    else
        echo "⏭️  Keeping existing services running."
        echo ""
        echo "📊 Current service status:"
        docker-compose ps
        echo ""
        echo "🎯 Access points:"
        echo "   • Monitoring Dashboard: http://localhost/monitoring/"
        echo "   • API Gateway: http://localhost:8000"
        echo "   • Load Balancer: http://localhost"
        exit 0
    fi
fi

echo "📋 Demo Components:"
echo "   • API Gateway (FastAPI) - Request routing and load balancing"
echo "   • Worker Service (FastAPI) - Task processing with auto-scaling"
echo "   • Redis - Caching and job queue"
echo "   • PostgreSQL - Persistent storage"
echo "   • Nginx - Load balancer"
echo "   • Monitoring Dashboard - Real-time metrics"
echo ""

echo "🔧 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to start..."
sleep 15

# Check service health
echo "🔍 Checking service health..."

# Function to check service health
check_service() {
    local name=$1
    local url=$2
    local timeout=${3:-10}
    
    if curl -s --max-time $timeout "$url" > /dev/null 2>&1; then
        echo "✅ $name is running on $url"
        return 0
    else
        echo "⚠️  $name may still be starting..."
        return 1
    fi
}

# Check each service
check_service "API Gateway" "http://localhost:8000"
check_service "Load Balancer" "http://localhost"
check_service "Monitoring Dashboard" "http://localhost:8080"

echo ""
echo "🎯 Demo is ready! Here's how to access it:"
echo ""
echo "📊 Monitoring Dashboard:"
echo "   http://localhost/monitoring/"
echo ""
echo "🔗 API Endpoints:"
echo "   • Health Check: http://localhost/api/status"
echo "   • Create Task: POST http://localhost/api/task"
echo "   • Get Metrics: http://localhost/api/metrics"
echo "   • Worker Status: http://localhost/worker/status"
echo ""
echo "🧪 Testing Commands:"
echo "   # Run basic tests"
echo "   ./test.sh"
echo ""
echo "   # Run scaling demonstration"
echo "   ./scale-demo.sh"
echo ""
echo "   # Load testing"
echo "   docker-compose --profile load-test up load-test"
echo ""
echo "📝 Example API calls:"
echo ""
echo "   # Create a task"
echo "   curl -X POST http://localhost/api/task \\"
echo "     -H 'Content-Type: application/json' \\"
echo "     -d '{\"type\": \"test\", \"data\": {\"message\": \"Hello World\"}}'"
echo ""
echo "   # Get system status"
echo "   curl http://localhost/api/status"
echo ""
echo "🔄 Scaling the system:"
echo "   # Scale up workers"
echo "   docker-compose up -d --scale worker-service=3"
echo ""
echo "   # Scale down workers"
echo "   docker-compose up -d --scale worker-service=1"
echo ""
echo "🛑 To stop the demo:"
echo "   ./stop.sh"
echo ""
echo "🧹 To clean up everything:"
echo "   ./setup.sh"
echo ""
echo "📚 Learn more about serverless scaling patterns in the System Design Interview Roadmap!"
echo ""
echo "🎉 Demo started successfully!" 