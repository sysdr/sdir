#!/bin/bash

set -e

echo "🚀 Starting Enterprise CI/CD Pipeline Demo..."

# Check Docker
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is required but not installed"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is required but not installed"
    exit 1
fi

# Build and start services
echo "🔨 Building services..."
docker-compose build --parallel

echo "🚀 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."

# Wait for health checks
max_wait=120
wait_time=0

check_service() {
    local service_url=$1
    local service_name=$2
    
    while [ $wait_time -lt $max_wait ]; do
        if curl -f -s "$service_url/health" > /dev/null 2>&1; then
            echo "✅ $service_name is ready"
            return 0
        fi
        sleep 2
        wait_time=$((wait_time + 2))
    done
    
    echo "❌ $service_name failed to start"
    return 1
}

# Check all services
check_service "http://localhost:3001" "Pipeline Orchestrator"
check_service "http://localhost:8080" "Frontend Service"
check_service "http://localhost:8081" "Backend Service" 
check_service "http://localhost:8082" "Database Service"

echo ""
echo "🎉 CI/CD Pipeline Demo is ready!"
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔧 Pipeline API: http://localhost:3001"
echo "🌐 Frontend Service: http://localhost:8080"
echo "🌐 Backend Service: http://localhost:8081"
echo "🌐 Database Service: http://localhost:8082"
echo ""
echo "📝 Demo Features:"
echo "  • Multi-stage pipelines with realistic build/test/security/deploy phases"
echo "  • Service-specific pipeline variations (database migrations, CDN deployment)"
echo "  • Security scanning with vulnerability findings simulation"
echo "  • Approval workflows for production deployments with auto-timeout"
echo "  • Real-time pipeline status updates via WebSocket"
echo "  • Enterprise metrics: Four Golden Signals (DORA metrics)"
echo "  • Stage failure rate tracking and analysis"
echo "  • Resource utilization and performance monitoring"
echo "  • Cross-service dependency management"
echo "  • Service health monitoring with realistic failure patterns"
echo "  • Automatic and manual pipeline triggers"
echo ""
echo "🧪 Try these advanced scenarios:"
echo "  1. Open the dashboard and observe the Four Golden Signals metrics"
echo "  2. Watch security scan results with different severity findings"
echo "  3. Trigger pipelines for different services and compare stage variations"
echo "  4. Monitor stage failure rates and system performance metrics"
echo "  5. Approve waiting stages and observe the approval workflow"
echo "  6. Observe how database migrations require additional approval gates"
echo "  7. Watch real-time metric updates every 10 seconds"
echo ""
echo "📊 Advanced Monitoring Features:"
echo "  • Deployment frequency tracking (last 24 hours)"
echo "  • Lead time measurement (commit to production)"
echo "  • Change failure rate calculation" 
echo "  • Stage-specific failure rate analysis"
echo "  • System performance indicators (cache hit rate, agent utilization)"
echo "  • Security vulnerability tracking and classification"
echo ""
echo "🛑 To stop: ./cleanup.sh"
