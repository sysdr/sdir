#!/bin/bash

# Error Budget Demo - Main Script

set -e

echo "🎯 Error Budget Balancing Demo"
echo "================================"

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker is not running. Please start Docker and try again."
        exit 1
    fi
}

# Function to install dependencies
install_dependencies() {
    echo "📦 Installing dependencies..."
    
    # Check if Python is available
    if ! command -v python3 &> /dev/null; then
        echo "❌ Python 3 is required but not installed."
        exit 1
    fi
    
    # Install Python packages
    pip3 install pytest requests aiohttp > /dev/null 2>&1 || true
    echo "✅ Dependencies installed"
}

# Function to build and start services
start_services() {
    echo "🚀 Building and starting services..."
    
    # Build and start with docker-compose
    docker-compose down --remove-orphans >/dev/null 2>&1 || true
    docker-compose build --quiet
    docker-compose up -d
    
    echo "⏳ Waiting for services to be ready..."
    sleep 10
    
    # Wait for dashboard to be accessible
    for i in {1..30}; do
        if curl -s http://localhost:3000 >/dev/null 2>&1; then
            echo "✅ Services are ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "❌ Services failed to start properly"
            docker-compose logs --tail=20
            exit 1
        fi
        sleep 2
    done
}

# Function to run tests
run_tests() {
    echo "🧪 Running tests..."
    python3 scripts/run_tests.py
}

# Function to show demo information
show_demo_info() {
    echo ""
    echo "🎉 Error Budget Demo is running!"
    echo "================================"
    echo ""
    echo "🌐 Access Points:"
    echo "   Dashboard: http://localhost:3000"
    echo "   API:       http://localhost:3000/api/error-budgets"
    echo ""
    echo "🎮 Try these scenarios:"
    echo "   1. Monitor normal operation (all services healthy)"
    echo "   2. Increase error rates using the controls"
    echo "   3. Watch error budgets get consumed"
    echo "   4. Observe different budget statuses"
    echo ""
    echo "📊 Key Metrics to Watch:"
    echo "   • Success Rate vs SLA Target"
    echo "   • Error Budget Remaining"
    echo "   • Budget Status (healthy/critical/exhausted)"
    echo ""
    echo "⏹️  Stop demo: docker-compose down"
    echo "🧹 Cleanup: ./cleanup.sh"
}

# Main execution
main() {
    check_docker
    install_dependencies
    start_services
    run_tests
    show_demo_info
}

# Handle script arguments
case "${1:-}" in
    "test")
        run_tests
        ;;
    "stop")
        echo "⏹️ Stopping services..."
        docker-compose down
        echo "✅ Services stopped"
        ;;
    *)
        main
        ;;
esac
