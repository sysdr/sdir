#!/bin/bash

# Serverless Scaling Demo - Status Script
# System Design Interview Roadmap - Issue #101

set -e

echo "📊 Serverless Scaling Demo Status"
echo "================================="
echo ""

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]] || [[ ! -d "src" ]]; then
    echo "❌ This doesn't appear to be the serverless scaling demo directory."
    echo "Please run this script from the demo directory."
    exit 1
fi

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running."
    echo "💡 Please start Docker and try again."
    exit 1
fi

echo "🔍 Checking service status..."
echo ""

# Show Docker Compose status
echo "📋 Service Status:"
docker-compose ps
echo ""

# Check if any services are running
if docker-compose ps | grep -q "Up"; then
    echo "✅ Services are running!"
    echo ""
    
    # Function to check service health
    check_service() {
        local name=$1
        local url=$2
        local timeout=${3:-5}
        
        if curl -s --max-time $timeout "$url" > /dev/null 2>&1; then
            echo "✅ $name: Healthy"
            return 0
        else
            echo "⚠️  $name: Unreachable"
            return 1
        fi
    }
    
    echo "🏥 Health Check:"
    check_service "API Gateway" "http://localhost:8000"
    check_service "Load Balancer" "http://localhost"
    check_service "Monitoring Dashboard" "http://localhost:8080"
    
    echo ""
    echo "🎯 Access Points:"
    echo "   📊 Monitoring Dashboard: http://localhost/monitoring/"
    echo "   🔗 API Gateway: http://localhost:8000"
    echo "   ⚖️  Load Balancer: http://localhost"
    echo "   🛠️  Worker Service: http://localhost/worker/status"
    echo ""
    
    echo "🧪 Quick Tests:"
    echo "   # System status"
    echo "   curl http://localhost/api/status"
    echo ""
    echo "   # Create a task"
    echo "   curl -X POST http://localhost/api/task \\"
    echo "     -H 'Content-Type: application/json' \\"
    echo "     -d '{\"type\": \"test\", \"data\": {\"message\": \"Hello\"}}'"
    echo ""
    
    echo "🔄 Management Commands:"
    echo "   # Stop services: ./stop.sh"
    echo "   # Restart services: ./start.sh"
    echo "   # Run tests: ./test.sh"
    echo "   # Scaling demo: ./scale-demo.sh"
    echo "   # Load testing: docker-compose --profile load-test up load-test"
    echo ""
    
    # Show recent logs if available
    echo "📝 Recent Activity:"
    echo "   (Last 5 lines from each service)"
    echo ""
    
    for service in api-gateway worker-service monitoring; do
        if docker-compose ps | grep -q "$service.*Up"; then
            echo "🔸 $service:"
            docker-compose logs --tail=5 "$service" 2>/dev/null | sed 's/^/   /' || echo "   No recent logs"
            echo ""
        fi
    done
    
else
    echo "❌ No services are currently running."
    echo ""
    echo "💡 To start the demo:"
    echo "   ./start.sh"
    echo ""
    echo "📚 For more information:"
    echo "   cat README.md"
fi

echo "📊 Status check completed!" 