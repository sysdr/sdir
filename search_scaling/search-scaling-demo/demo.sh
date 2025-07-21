#!/bin/bash

# Search Scaling Demo - One-Click Demo Script
# This script provides a complete demo experience from start to finish

set -e  # Exit on any error

echo "🎯 Search Scaling Demo - Complete Experience"
echo "============================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_demo() {
    echo -e "${PURPLE}[DEMO]${NC} $1"
}

print_performance() {
    echo -e "${CYAN}[PERF]${NC} $1"
}

# Function to wait for user input
wait_for_user() {
    echo ""
    echo -n "Press Enter to continue..."
    read -r
}

# Function to show demo menu
show_menu() {
    echo ""
    print_demo "🎯 Demo Menu - Choose an option:"
    echo ""
    echo "1. 🚀 Complete Demo (Build + Start + Test)"
    echo "2. 🔨 Build Only"
    echo "3. ▶️  Start Demo"
    echo "4. 🔍 Run Performance Tests"
    echo "5. 📊 Interactive Testing"
    echo "6. 🧹 Cleanup"
    echo "7. 📚 Show Documentation"
    echo "8. ❌ Exit"
    echo ""
    echo -n "Enter your choice (1-8): "
}

# Function to run complete demo
run_complete_demo() {
    print_demo "🚀 Starting Complete Demo Experience"
    echo ""
    
    # Step 1: Build
    print_status "Step 1: Building the environment..."
    ./build.sh
    wait_for_user
    
    # Step 2: Start
    print_status "Step 2: Starting the demo..."
    ./start-demo.sh &
    START_PID=$!
    
    # Wait for demo to be ready
    print_status "Waiting for demo to be ready..."
    sleep 30
    
    # Check if demo is running
    if curl -s http://localhost:5000/health > /dev/null 2>&1; then
        print_success "Demo is running successfully!"
    else
        print_warning "Demo may still be starting up..."
    fi
    
    wait_for_user
    
    # Step 3: Show demo features
    print_status "Step 3: Demo Features Overview"
    echo ""
    print_demo "🌐 Web Interface: http://localhost:5000"
    echo "   • Modern search interface"
    echo "   • Real-time performance metrics"
    echo "   • Search type comparison"
    echo "   • Interactive testing tools"
    echo ""
    print_demo "🔧 Available Services:"
    echo "   • Flask App: http://localhost:5000"
    echo "   • Elasticsearch: http://localhost:9200"
    echo "   • Redis: localhost:6379"
    echo "   • PostgreSQL: localhost:5432"
    echo ""
    
    wait_for_user
    
    # Step 4: Run performance test
    print_status "Step 4: Running Performance Comparison Test..."
    ./simulate-load.sh comparison
    wait_for_user
    
    # Step 5: Interactive testing
    print_status "Step 5: Interactive Testing Mode"
    echo ""
    print_demo "You can now:"
    echo "   • Open http://localhost:5000 in your browser"
    echo "   • Try different search queries"
    echo "   • Compare search types"
    echo "   • Monitor real-time metrics"
    echo ""
    print_demo "Or run additional tests:"
    echo "   • ./simulate-load.sh stress     # Stress testing"
    echo "   • ./simulate-load.sh interactive # Interactive mode"
    echo ""
    
    print_success "Complete demo experience finished!"
    print_status "Demo is still running. Use './cleanup.sh' to stop when done."
}

# Function to show documentation
show_documentation() {
    print_demo "📚 Documentation Overview"
    echo ""
    echo "📖 Available Documentation:"
    echo "   • README.md - Project overview and quick start"
    echo "   • demo-guide.md - Complete detailed guide"
    echo ""
    echo "🔗 Quick Links:"
    echo "   • Web Interface: http://localhost:5000"
    echo "   • Health Check: curl http://localhost:5000/health"
    echo "   • Metrics: curl http://localhost:5000/metrics"
    echo ""
    echo "📋 Key Commands:"
    echo "   • ./build.sh - Build the environment"
    echo "   • ./start-demo.sh - Start the demo"
    echo "   • ./simulate-load.sh [mode] - Run performance tests"
    echo "   • ./cleanup.sh - Stop and cleanup"
    echo ""
    echo "🎯 Demo Modes:"
    echo "   • comparison - Compare all search types"
    echo "   • stress - Test with concurrent users"
    echo "   • interactive - Interactive query testing"
    echo ""
}

# Function to cleanup
cleanup_demo() {
    print_status "Cleaning up demo environment..."
    
    if [ -f "./cleanup.sh" ]; then
        ./cleanup.sh
    else
        docker-compose down -v
        docker system prune -f
    fi
    
    print_success "Cleanup completed!"
}

# Main demo function
main() {
    while true; do
        show_menu
        read -r choice
        
        case $choice in
            1)
                run_complete_demo
                ;;
            2)
                print_status "Building environment..."
                ./build.sh
                wait_for_user
                ;;
            3)
                print_status "Starting demo..."
                ./start-demo.sh
                ;;
            4)
                print_status "Running performance tests..."
                ./simulate-load.sh comparison
                wait_for_user
                ;;
            5)
                print_status "Starting interactive testing..."
                ./simulate-load.sh interactive
                ;;
            6)
                cleanup_demo
                wait_for_user
                ;;
            7)
                show_documentation
                wait_for_user
                ;;
            8)
                print_status "Exiting demo..."
                exit 0
                ;;
            *)
                print_error "Invalid choice. Please enter a number between 1-8."
                wait_for_user
                ;;
        esac
    done
}

# Check if required scripts exist
check_requirements() {
    required_scripts=("build.sh" "start-demo.sh" "simulate-load.sh")
    
    for script in "${required_scripts[@]}"; do
        if [ ! -f "$script" ]; then
            print_error "Required script not found: $script"
            exit 1
        fi
        
        if [ ! -x "$script" ]; then
            print_warning "Making $script executable..."
            chmod +x "$script"
        fi
    done
    
    print_success "All requirements checked"
}

# Show welcome message
show_welcome() {
    echo ""
    print_demo "🎯 Welcome to the Search Scaling Demo!"
    echo ""
    echo "This demo showcases:"
    echo "   • PostgreSQL full-text search"
    echo "   • Elasticsearch advanced search"
    echo "   • Redis caching for performance"
    echo "   • Real-time performance metrics"
    echo "   • Load simulation and testing"
    echo ""
    echo "Perfect for:"
    echo "   • System design interviews"
    echo "   • Performance testing"
    echo "   • Learning search technologies"
    echo "   • Technical presentations"
    echo ""
}

# Run main function
show_welcome
check_requirements
main "$@" 