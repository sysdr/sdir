#!/bin/bash

# UI Test Runner Script for Zero-Downtime Dashboard

set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

info() {
    echo -e "${BLUE}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"
}

# Check if dashboard is running
check_dashboard() {
    if ! curl -s http://localhost:3000 > /dev/null 2>&1; then
        error "Dashboard is not running on http://localhost:3000"
        error "Please start the dashboard first with: ./run_demo.sh start"
        exit 1
    fi
    log "Dashboard is running on http://localhost:3000"
}

# Install dependencies if needed
install_dependencies() {
    if [ ! -d "node_modules" ]; then
        log "Installing npm dependencies..."
        npm install
    fi
    
    if [ ! -f "node_modules/.bin/playwright" ]; then
        log "Installing Playwright browsers..."
        npx playwright install
    fi
}

# Run tests
run_tests() {
    local test_type=${1:-"all"}
    
    case $test_type in
        "ui")
            log "Running UI tests only..."
            npm run test:ui
            ;;
        "headed")
            log "Running tests in headed mode..."
            npm run test:headed
            ;;
        "debug")
            log "Running tests in debug mode..."
            npm run test:debug
            ;;
        "all")
            log "Running all tests..."
            npm test
            ;;
        *)
            error "Unknown test type: $test_type"
            echo "Usage: $0 {ui|headed|debug|all}"
            exit 1
            ;;
    esac
}

# Show test results
show_results() {
    if [ -f "test-results/results.json" ]; then
        log "Test results saved to test-results/results.json"
    fi
    
    if [ -d "playwright-report" ]; then
        log "HTML report available. Run 'npm run test:report' to view it"
    fi
}

# Main execution
main() {
    log "Starting UI Test Suite for Zero-Downtime Dashboard"
    
    # Check prerequisites
    check_dashboard
    install_dependencies
    
    # Run tests
    run_tests "${1:-all}"
    
    # Show results
    show_results
    
    log "UI tests completed!"
}

# Handle command line arguments
case "${1:-all}" in
    "ui"|"headed"|"debug"|"all")
        main "$1"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 {ui|headed|debug|all|help}"
        echo "  ui     - Run UI tests only"
        echo "  headed - Run tests in headed mode (visible browser)"
        echo "  debug  - Run tests in debug mode"
        echo "  all    - Run all tests (default)"
        echo "  help   - Show this help message"
        ;;
    *)
        error "Unknown option: $1"
        echo "Use '$0 help' for usage information"
        exit 1
        ;;
esac 