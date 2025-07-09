#!/bin/bash

# Fanout Demo Restart Script
# This script restarts the fanout demo application

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

# Main execution
main() {
    echo -e "${BLUE}================================${NC}"
    echo -e "${BLUE}  Fanout Demo Restart Script${NC}"
    echo -e "${BLUE}================================${NC}"
    echo ""
    
    # Change to script directory
    cd "$(dirname "$0")"
    
    # Check if start and stop scripts exist
    if [[ ! -f "./start.sh" ]] || [[ ! -f "./stop.sh" ]]; then
        print_error "Start or stop script not found. Please ensure both start.sh and stop.sh exist."
        exit 1
    fi
    
    # Stop the application
    print_status "Stopping the application..."
    if ./stop.sh > /dev/null 2>&1; then
        print_success "Application stopped"
    else
        print_warning "No running containers to stop"
    fi
    
    # Wait a moment for cleanup
    sleep 3
    
    # Start the application
    print_status "Starting the application..."
    ./start.sh
    
    print_success "Restart completed successfully!"
}

# Run main function
main "$@" 