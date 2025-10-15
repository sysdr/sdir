#!/bin/bash

set -e

echo "🚀 Black Friday Load Preparation Demo"
echo "===================================="
echo ""
echo "This demo simulates a complete e-commerce system under Black Friday load"
echo "with auto-scaling, circuit breakers, and intelligent load shedding."
echo ""

# Check dependencies
check_dependencies() {
    echo "🔍 Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is required but not installed"
        echo "   Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo "❌ Docker Compose is required but not installed"
        echo "   Please install Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    echo "✅ All dependencies are available"
}

# Build and start services
start_services() {
    echo ""
    echo "🏗️  Building and starting services..."
    echo "This may take a few minutes on first run..."
    
    docker-compose build
    docker-compose up -d
    
    echo ""
    echo "⏳ Waiting for services to be ready..."
    
    # Wait for backend to be ready
    for i in {1..30}; do
        if curl -s http://localhost:3001/health > /dev/null 2>&1; then
            echo "✅ Backend is ready"
            break
        fi
        echo "   Waiting for backend... ($i/30)"
        sleep 2
    done
    
    # Wait for frontend to be ready
    for i in {1..15}; do
        if curl -s http://localhost:3000 > /dev/null 2>&1; then
            echo "✅ Frontend is ready"
            break
        fi
        echo "   Waiting for frontend... ($i/15)"
        sleep 2
    done
}

# Run tests
run_tests() {
    echo ""
    echo "🧪 Running system tests..."
    
    # Test health endpoint
    if curl -s http://localhost:3001/health | grep -q "healthy"; then
        echo "✅ Health check passed"
    else
        echo "❌ Health check failed"
        return 1
    fi
    
    # Test API endpoint
    if curl -s http://localhost:3001/api/products | grep -q "products"; then
        echo "✅ API endpoint test passed"
    else
        echo "❌ API endpoint test failed"
        return 1
    fi
    
    # Test metrics endpoint
    if curl -s http://localhost:3001/metrics | grep -q "http_request_duration_ms"; then
        echo "✅ Metrics endpoint test passed"
    else
        echo "❌ Metrics endpoint test failed"
        return 1
    fi
}

# Show access information
show_access_info() {
    echo ""
    echo "🎉 Demo is ready! Access points:"
    echo "================================"
    echo ""
    echo "📊 Main Dashboard:    http://localhost:3000"
    echo "   - Real-time metrics and load testing controls"
    echo "   - Circuit breaker status visualization"
    echo "   - Auto-scaling event timeline"
    echo ""
    echo "🔧 API Endpoints:     http://localhost:3001"
    echo "   - /health           - Health check"
    echo "   - /api/products     - Main API endpoint"
    echo "   - /metrics          - Prometheus metrics"
    echo ""
    echo "📈 Prometheus:        http://localhost:9090"
    echo "   - Raw metrics and queries"
    echo ""
    echo "📊 Grafana:           http://localhost:3002"
    echo "   - Username: admin / Password: admin"
    echo "   - Advanced dashboards and alerting"
    echo ""
}

# Show demo instructions
show_demo_instructions() {
    echo "🎯 How to Experience Black Friday Load:"
    echo "======================================"
    echo ""
    echo "1. Open the main dashboard: http://localhost:3000"
    echo ""
    echo "2. Observe the normal traffic baseline:"
    echo "   - Low RPS (< 100 requests/second)"
    echo "   - Circuit breaker in CLOSED state"
    echo "   - Normal response times (< 50ms)"
    echo ""
    echo "3. Click '🚀 Start Black Friday Load Test' to simulate:"
    echo "   - Traffic spike to 3000+ RPS (300x normal)"
    echo "   - Circuit breaker state transitions"
    echo "   - Auto-scaling events"
    echo "   - Load shedding activation"
    echo ""
    echo "4. Watch the real-time charts show:"
    echo "   - Response time increases under load"
    echo "   - Circuit breaker opening when overloaded"
    echo "   - System recovery and stabilization"
    echo ""
    echo "5. Optional: Run automated load generator:"
    echo "   docker-compose --profile load-test up load-generator"
    echo ""
    echo "💡 Tips:"
    echo "   - Leave the dashboard open to see live updates"
    echo "   - Check the scaling events list for auto-scaling activity"
    echo "   - Try multiple load test cycles to see pattern recognition"
    echo ""
}

# Main execution
main() {
    check_dependencies
    start_services
    run_tests
    show_access_info
    show_demo_instructions
    
    echo "🎊 Demo is fully operational!"
    echo ""
    echo "Press Ctrl+C to stop all services when done"
    echo "Or run './cleanup.sh' to clean up everything"
}

main
