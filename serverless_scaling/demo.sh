#!/bin/bash

# Serverless Scaling Demo
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
sleep 10

# Check if services are healthy
echo "🔍 Checking service health..."

# Check API Gateway
if curl -s http://localhost:8000/ > /dev/null; then
    echo "✅ API Gateway is running on http://localhost:8000"
else
    echo "⚠️  API Gateway may still be starting..."
fi

# Check Nginx
if curl -s http://localhost/ > /dev/null; then
    echo "✅ Load Balancer is running on http://localhost"
else
    echo "⚠️  Load Balancer may still be starting..."
fi

# Check Monitoring
if curl -s http://localhost:8080/ > /dev/null; then
    echo "✅ Monitoring Dashboard is running on http://localhost:8080"
else
    echo "⚠️  Monitoring Dashboard may still be starting..."
fi

echo ""
echo "🎯 Demo is ready! Here's how to test it:"
echo ""
echo "📊 Monitoring Dashboard:"
echo "   http://localhost:8080"
echo ""
echo "🔗 API Endpoints:"
echo "   • Health Check: http://localhost/api/status"
echo "   • Create Task: POST http://localhost/api/task"
echo "   • Get Metrics: http://localhost/api/metrics"
echo "   • Worker Status: http://localhost:8001/worker/status"
echo ""
echo "🧪 Load Testing:"
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
echo "   # Get worker status"
echo "   curl http://localhost:8001/worker/status"
echo ""
echo "🔄 Scaling the system:"
echo "   # Scale up workers"
echo "   docker-compose up -d --scale worker-service=3"
echo ""
echo "   # Scale down workers"
echo "   docker-compose up -d --scale worker-service=1"
echo ""
echo "🛑 To stop the demo:"
echo "   docker-compose down"
echo ""
echo "🧹 To clean up everything:"
echo "   ./setup.sh"
echo ""
echo "📚 Learn more about serverless scaling patterns in the System Design Interview Roadmap!"
echo "" 