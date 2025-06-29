#!/bin/bash

mkdir -p static

set -e

echo "🚀 Setting up Multi-Region Architecture Demo..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check dependencies
check_dependencies() {
    print_status "🔍 Checking dependencies..."
    
    if ! command -v python3 &> /dev/null; then
        print_error "Python 3 is required but not installed."
        exit 1
    fi
    
    if ! command -v docker &> /dev/null; then
        print_warning "Docker not found. Will run in local mode."
        USE_DOCKER=false
    else
        USE_DOCKER=true
    fi
    
    python3 --version
}

# Install dependencies and run
install_and_run() {
    # Ensure static directory exists before any Python code runs
    mkdir -p static
    print_status "📦 Installing dependencies..."
    
    # Create virtual environment if it doesn't exist
    if [ ! -d "venv" ]; then
        python3 -m venv venv
    fi
    
    # Activate virtual environment
    source venv/bin/activate
    
    # Upgrade pip
    pip install --upgrade pip
    
    # Install requirements
    pip install -r requirements.txt
    
    print_status "🧪 Running tests..."
    cd tests
    python -m pytest test_multiregion.py -v
    cd ..
    
    print_status "🚀 Starting the demo application..."
    
    if [ "$USE_DOCKER" = true ]; then
        print_status "🐳 Building and running with Docker..."
        docker-compose up --build -d
        
        # Wait for services to start
        sleep 5
        
        # Check if services are running
        if docker-compose ps | grep -q "Up"; then
            print_status "✅ Docker services are running!"
        else
            print_warning "⚠️ Docker services may not be fully ready. Check logs with: docker-compose logs"
        fi
    else
        print_status "💻 Running in local mode..."
        
        # Start the application in background and save PID
        python app/main.py &
        echo $! > .demo_pid
        
        # Wait for application to start
        sleep 3
    fi
    
    # Test if the application is responding
    print_status "🔍 Testing application health..."
    for i in {1..10}; do
        if curl -s http://localhost:5000/api/regions > /dev/null; then
            print_status "✅ Application is responding!"
            break
        fi
        if [ $i -eq 10 ]; then
            print_error "❌ Application failed to start properly"
            exit 1
        fi
        sleep 2
    done
}

# Show demo instructions
show_instructions() {
    print_status "🎯 Demo is ready!"
    echo ""
    echo -e "${GREEN}🌐 Dashboard URL:${NC} http://localhost:5000"
    echo -e "${GREEN}📊 API Endpoints:${NC}"
    echo "   • GET  /api/regions     - View all regions"
    echo "   • POST /api/request     - Simulate user request"
    echo "   • POST /api/replicate   - Trigger data replication"
    echo "   • GET  /api/metrics     - System metrics"
    echo ""
    echo -e "${BLUE}🎮 Try these scenarios:${NC}"
    echo "   1. 📡 Simulate requests to see load balancing"
    echo "   2. ⚠️ Degrade a region to see failover behavior"
    echo "   3. 💥 Fail a region completely to test circuit breakers"
    echo "   4. 🔄 Trigger replication to see data sync"
    echo "   5. 🏥 Heal regions to restore normal operation"
    echo ""
    echo -e "${YELLOW}📝 What you'll observe:${NC}"
    echo "   • Real-time region health monitoring"
    echo "   • Circuit breaker state changes (Closed/Open/Half-Open)"
    echo "   • Latency differences between regions"
    echo "   • Automatic traffic routing to healthy regions"
    echo "   • Data replication across multiple regions"
    echo "   • Graceful degradation during failures"
    echo ""
    echo -e "${GREEN}🛑 To stop the demo:${NC} ./cleanup.sh"
    echo ""
    
    # Try to open browser automatically
    if command -v open > /dev/null; then
        open http://localhost:5000
    elif command -v xdg-open > /dev/null; then
        xdg-open http://localhost:5000
    fi
}

# Main execution
main() {
    print_status "🚀 Multi-Region Architecture Demo Setup"
    echo "========================================"
    
    check_dependencies
    install_and_run
    show_instructions
    
    print_status "✅ Demo setup completed successfully!"
    print_status "📊 Monitor the dashboard and try different failure scenarios"
    print_status "🔍 Check the Activity Log for real-time system events"
}

# Run main function
main