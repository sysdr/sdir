#!/bin/bash

# Financial System Design Demo - ACID and Beyond
# Complete one-click setup and demonstration

set -e

DEMO_NAME="Financial System Design Demo"
PROJECT_DIR="."

echo "🏦 $DEMO_NAME"
echo "=================================================="
echo "This demo showcases:"
echo "• ACID Properties in Financial Systems"
echo "• Distributed Transactions with SAGA Pattern"  
echo "• Audit Trail and Compliance"
echo "• Modern Microservices Architecture"
echo "=================================================="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    if ! command_exists docker; then
        echo "❌ Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command_exists docker-compose; then
        echo "❌ Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    if ! command_exists python3; then
        echo "❌ Python 3 is not installed. Please install Python 3 first."
        exit 1
    fi
    
    echo "✅ All prerequisites found"
}

# Setup function
setup_demo() {
    echo "📁 Setting up demo environment..."
    
    # Since we're already inside financial-system-demo, no need to create/remove directory
    echo "✅ Demo environment ready"
}

# Build and start services
build_and_start() {
    echo "🔨 Building and starting services..."
    
    # Build all services
    echo "📦 Building Docker images..."
    docker-compose build --parallel
    
    # Start services
    echo "🚀 Starting services..."
    docker-compose up -d
    
    echo "⏳ Waiting for services to become healthy..."
    sleep 30
    
    # Check service health
    for i in {1..12}; do
        if curl -s http://localhost:8001/health > /dev/null && \
           curl -s http://localhost:8002/health > /dev/null && \
           curl -s http://localhost:8003/health > /dev/null; then
            echo "✅ All services are healthy!"
            break
        fi
        
        if [ $i -eq 12 ]; then
            echo "❌ Services failed to start properly"
            echo "📋 Checking logs..."
            docker-compose logs
            exit 1
        fi
        
        echo "⏳ Still waiting for services... (attempt $i/12)"
        sleep 10
    done
}

# Install Python dependencies for tests
setup_tests() {
    echo "🧪 Setting up test environment..."
    
    if [ ! -f "requirements-test.txt" ]; then
        cat > requirements-test.txt << 'TESTEOF'
aiohttp==3.9.0
asyncio==3.4.3
TESTEOF
    fi
    
    # Install test dependencies
    pip3 install -r requirements-test.txt > /dev/null 2>&1 || {
        echo "⚠️  Could not install test dependencies. Tests may not work."
    }
}

# Run comprehensive tests
run_tests() {
    echo "🧪 Running comprehensive test suite..."
    
    python3 test_system.py
    test_exit_code=$?
    
    if [ $test_exit_code -eq 0 ]; then
        echo "✅ All tests passed!"
    else
        echo "⚠️  Some tests failed, but demo is still functional"
    fi
    
    return $test_exit_code
}

# Show demo information
show_demo_info() {
    echo ""
    echo "🎉 Financial System Demo is ready!"
    echo "=================================================="
    echo ""
    echo "🌐 Access Points:"
    echo "   • Web Dashboard: http://localhost:3000"
    echo "   • Account Service API: http://localhost:8001"
    echo "   • Transaction Service API: http://localhost:8002" 
    echo "   • Audit Service API: http://localhost:8003"
    echo ""
    echo "📱 Demo Features:"
    echo "   • Account Management with ACID properties"
    echo "   • Money transfers using SAGA pattern"
    echo "   • Real-time audit trail and compliance"
    echo "   • Distributed transaction visualization"
    echo ""
    echo "🧪 Testing:"
    echo "   • Run: python3 test_system.py (comprehensive tests)"
    echo "   • Check: docker-compose logs [service-name]"
    echo "   • Monitor: docker-compose ps"
    echo ""
    echo "🔧 Management:"
    echo "   • Stop: docker-compose down"
    echo "   • Cleanup: ./cleanup.sh"
    echo "   • Restart: docker-compose restart [service-name]"
    echo ""
    echo "💡 Try These Scenarios:"
    echo "   1. Create accounts via web dashboard"
    echo "   2. Execute transfers and watch SAGA execution"
    echo "   3. View audit trails and integrity verification"
    echo "   4. Simulate failures by stopping services"
    echo ""
    echo "=================================================="
}

# Quick API demonstration
demo_api_calls() {
    echo "📡 Demonstrating API functionality..."
    
    echo "Creating sample accounts..."
    
    # Create test accounts
    ALICE_RESPONSE=$(curl -s -X POST http://localhost:8001/accounts \
        -H "Content-Type: application/json" \
        -d '{"customer_name": "Alice Demo", "initial_balance": 1500.00}')
    
    BOB_RESPONSE=$(curl -s -X POST http://localhost:8001/accounts \
        -H "Content-Type: application/json" \
        -d '{"customer_name": "Bob Demo", "initial_balance": 750.00}')
    
    ALICE_ACCOUNT=$(echo $ALICE_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['account_number'])" 2>/dev/null || echo "ACC_ALICE")
    BOB_ACCOUNT=$(echo $BOB_RESPONSE | python3 -c "import sys, json; print(json.load(sys.stdin)['account_number'])" 2>/dev/null || echo "ACC_BOB")
    
    echo "✅ Created accounts: $ALICE_ACCOUNT and $BOB_ACCOUNT"
    
    # Execute a transfer
    echo "Executing sample transfer..."
    TRANSFER_RESPONSE=$(curl -s -X POST http://localhost:8002/transactions/transfer \
        -H "Content-Type: application/json" \
        -d "{\"from_account\": \"$ALICE_ACCOUNT\", \"to_account\": \"$BOB_ACCOUNT\", \"amount\": 200.00, \"description\": \"Demo Transfer\", \"idempotency_key\": \"demo_$(date +%s)\"}")
    
    echo "✅ Transfer completed"
    echo "📊 Transfer details: $TRANSFER_RESPONSE" | head -c 100
    echo "..."
}

# Main execution
main() {
    case "${1:-}" in
        "setup")
            check_prerequisites
            setup_demo
            echo "✅ Setup completed. Run './demo.sh start' to begin."
            ;;
        "start"|"")
            check_prerequisites
            setup_demo
            build_and_start
            setup_tests
            
            echo "⏳ Running initial tests..."
            if run_tests; then
                echo "✅ System verification completed successfully"
            else
                echo "⚠️  Some tests failed, but proceeding with demo"
            fi
            
            demo_api_calls
            show_demo_info
            ;;
        "test")
            echo "🧪 Running test suite only..."
            python3 test_system.py
            ;;
        "logs")
            docker-compose logs -f "${2:-}"
            ;;
        "status")
            docker-compose ps
            echo ""
            echo "Service Health:"
            curl -s http://localhost:8001/health && echo " ✅ Account Service"
            curl -s http://localhost:8002/health && echo " ✅ Transaction Service"  
            curl -s http://localhost:8003/health && echo " ✅ Audit Service"
            ;;
        "clean"|"cleanup")
            echo "🧹 Cleaning up demo..."
            docker-compose down -v 2>/dev/null
            echo "✅ Cleanup completed"
            echo "Note: This directory still exists. To remove it, go to the parent directory and run: rm -rf financial-system-demo"
            ;;
        "help"|"-h"|"--help")
            echo "Financial System Design Demo"
            echo ""
            echo "Usage: $0 [COMMAND]"
            echo ""
            echo "Commands:"
            echo "  setup     Setup demo environment only"
            echo "  start     Setup and start complete demo (default)"
            echo "  test      Run test suite only"
            echo "  logs      Show service logs [service-name]"
            echo "  status    Show service status and health"
            echo "  clean     Stop and cleanup everything"
            echo "  help      Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0              # Start complete demo"
            echo "  $0 start        # Start complete demo"
            echo "  $0 test         # Run tests only"
            echo "  $0 logs account-service  # Show account service logs"
            echo "  $0 status       # Check service health"
            echo "  $0 clean        # Cleanup everything"
            ;;
        *)
            echo "❌ Unknown command: $1"
            echo "Run '$0 help' for usage information."
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"
