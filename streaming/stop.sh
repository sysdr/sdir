#!/bin/bash

# Data Streaming Architecture Demo Stop Script
# This script stops all demo services and cleans up

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[$(date '+%H:%M:%S')]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date '+%H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date '+%H:%M:%S')]${NC} $1"
}

print_header() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# Check if we're in the right directory
if [ ! -f "setup.sh" ]; then
    print_error "Error: setup.sh not found. Please run this script from the project root directory."
    exit 1
fi

print_header "🛑 Stopping Data Streaming Architecture Demo"

# Navigate to the demo directory
cd data-streaming-demo

print_status "Stopping all demo services..."

# Stop all services
docker-compose down

print_status "Checking if any containers are still running..."

# Check if any containers are still running
if docker-compose ps | grep -q "Up"; then
    print_warning "Some containers are still running. Force stopping..."
    docker-compose down --remove-orphans
fi

print_status "Cleaning up Docker resources..."

# Remove any dangling images and containers
docker system prune -f

print_header "✅ Demo Successfully Stopped!"
echo
echo -e "${GREEN}🎯 All services have been stopped:${NC}"
echo "   • Kafka and Zookeeper"
echo "   • Redis cache"
echo "   • Data producers (user-events, metrics)"
echo "   • Data consumers (analytics, notifications, recommendations)"
echo "   • Web dashboard"
echo
echo -e "${YELLOW}📋 Cleanup Summary:${NC}"
echo "   • All containers stopped"
echo "   • Docker resources cleaned up"
echo "   • Ports 8080, 9092, 6379, 2181 are now available"
echo
echo -e "${CYAN}🔧 To restart the demo:${NC}"
echo "   • Run: ./demo.sh"
echo "   • Or run: ./setup.sh"
echo
echo -e "${GREEN}🎬 Demo stopped successfully!${NC}"
echo -e "${GREEN}All resources have been cleaned up.${NC}"
echo
print_header "Demo Stopped! 🛑" 