#!/bin/bash

# Connection Pool Demo - Main Demo Script
set -e

echo "🔗 Connection Pool Demo - System Design Mastery"
echo "=================================================="

# Check dependencies
check_dependencies() {
    echo "🔍 Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is required but not installed"
        echo "Please install Docker: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo "❌ Docker Compose is required but not installed"
        echo "Please install Docker Compose: https://docs.docker.com/compose/install/"
        exit 1
    fi
    
    echo "✅ All dependencies are available"
}

# Build and start services
start_services() {
    echo "🐳 Building and starting services..."
    
    # Build and start all services
    docker-compose up --build -d
    
    echo "⏳ Waiting for services to be ready..."
    
    # Wait for PostgreSQL
    echo "   Waiting for PostgreSQL..."
    until docker-compose exec -T postgres pg_isready -U demo -d connection_demo; do
        sleep 2
    done
    
    # Wait for Redis
    echo "   Waiting for Redis..."
    until docker-compose exec -T redis redis-cli ping; do
        sleep 2
    done
    
    # Wait for application
    echo "   Waiting for Application..."
    for i in {1..30}; do
        if curl -s http://localhost:5000/api/health > /dev/null; then
            break
        fi
        sleep 2
    done
    
    echo "✅ All services are ready!"
}

# Run tests
run_tests() {
    echo "🧪 Running test suite..."
    
    # Install test dependencies in app container
    docker-compose exec app pip install pytest requests
    
    # Run tests
    docker-compose exec app python -m pytest tests/ -v
    
    echo "✅ All tests passed!"
}

# Display demo information
show_demo_info() {
    echo "🎉 Connection Pool Demo is ready!"
    echo ""
    echo "Access Points:"
    echo "=============="
    echo "🌐 Web Dashboard: http://localhost:5000"
    echo "📊 API Health: http://localhost:5000/api/health"
    echo "📈 Metrics: http://localhost:5000/api/metrics"
    echo ""
    echo "Database Access:"
    echo "==============="
    echo "🐘 PostgreSQL: localhost:5432"
    echo "   Database: connection_demo"
    echo "   Username: demo"
    echo "   Password: demo123"
    echo ""
    echo "Demo Features:"
    echo "============="
    echo "• Real-time connection pool monitoring"
    echo "• Interactive test scenarios"
    echo "• Performance metrics visualization"
    echo "• Pool configuration management"
    echo "• Connection state visualization"
    echo ""
    echo "Test Scenarios:"
    echo "=============="
    echo "• Normal Load - Typical application usage"
    echo "• High Load - Stress testing with many concurrent requests"
    echo "• Pool Exhaustion - Trigger pool exhaustion conditions"
    echo "• Connection Leaks - Simulate connection leak scenarios"
    echo "• Database Slowness - Test behavior with slow database responses"
    echo ""
    echo "Learning Objectives:"
    echo "==================="
    echo "• Understand connection pool sizing trade-offs"
    echo "• Observe pool exhaustion and recovery patterns"
    echo "• Learn to monitor pool health metrics"
    echo "• Experience different failure modes"
    echo "• Practice pool configuration optimization"
    echo ""
    echo "Next Steps:"
    echo "==========="
    echo "1. Open http://localhost:5000 in your browser"
    echo "2. Try different test scenarios"
    echo "3. Experiment with pool configuration"
    echo "4. Monitor real-time metrics"
    echo "5. Analyze performance patterns"
    echo ""
    echo "To stop the demo: ./cleanup.sh"
    echo ""
}

# Run demonstration scenarios
run_demo_scenarios() {
    echo "🎭 Running demonstration scenarios..."
    
    echo "📊 1. Getting baseline metrics..."
    curl -s http://localhost:5000/api/metrics | python3 -m json.tool
    
    echo ""
    echo "🔄 2. Running normal load scenario..."
    curl -s -X POST http://localhost:5000/api/scenarios/normal_load | python3 -m json.tool
    
    sleep 5
    
    echo ""
    echo "⚡ 3. Running high load scenario..."
    curl -s -X POST http://localhost:5000/api/scenarios/high_load | python3 -m json.tool
    
    sleep 10
    
    echo ""
    echo "📊 4. Getting updated metrics..."
    curl -s http://localhost:5000/api/metrics | python3 -m json.tool
    
    echo ""
    echo "✅ Demo scenarios completed!"
    echo "Open http://localhost:5000 to see real-time visualization"
}

# Main execution
main() {
    case "${1:-start}" in
        "start")
            check_dependencies
            start_services
            show_demo_info
            ;;
        "test")
            run_tests
            ;;
        "demo")
            run_demo_scenarios
            ;;
        "info")
            show_demo_info
            ;;
        "logs")
            docker-compose logs -f
            ;;
        "stop")
            echo "🛑 Stopping services..."
            docker-compose down
            echo "✅ Services stopped"
            ;;
        *)
            echo "Usage: $0 {start|test|demo|info|logs|stop}"
            echo ""
            echo "Commands:"
            echo "  start - Build and start the demo (default)"
            echo "  test  - Run the test suite"
            echo "  demo  - Run automated demo scenarios"
            echo "  info  - Show demo information"
            echo "  logs  - Show service logs"
            echo "  stop  - Stop all services"
            ;;
    esac
}

main "$@"
