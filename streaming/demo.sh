#!/bin/bash

# Data Streaming Architecture Demo Launcher
# This script builds and launches the complete streaming demo

set -e

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

print_header "🚀 Data Streaming Architecture Demo"
print_status "Starting demo build and launch..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    print_error "Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if Docker Compose is available
if ! command -v docker-compose > /dev/null 2>&1; then
    print_error "Docker Compose is not installed. Please install Docker Compose and try again."
    exit 1
fi

# Navigate to the demo directory
cd data-streaming-demo

print_status "Building and launching the streaming demo..."

# Build and start the services
docker-compose up --build -d

print_status "Waiting for services to be ready..."
sleep 30

# Check service health
print_status "Checking service health..."

# Check Kafka
if docker-compose exec -T kafka kafka-topics --bootstrap-server localhost:9092 --list > /dev/null 2>&1; then
    print_status "✓ Kafka is healthy"
else
    print_warning "⚠ Kafka is starting up..."
fi

# Check Redis
if docker-compose exec -T redis redis-cli ping > /dev/null 2>&1; then
    print_status "✓ Redis is healthy"
else
    print_warning "⚠ Redis is starting up..."
fi

# Wait a bit more for web dashboard
sleep 10

print_header "🎉 Demo Successfully Launched!"
echo
echo -e "${GREEN}📊 Dashboard:${NC}      http://localhost:8080"
echo -e "${GREEN}📈 Kafka UI:${NC}       http://localhost:9092"
echo -e "${GREEN}🔄 Redis:${NC}          localhost:6379"
echo
echo -e "${YELLOW}🎯 Features:${NC}"
echo "   • Real-time streaming pipeline"
echo "   • Lambda architecture pattern"
echo "   • Multiple consumer groups"
echo "   • Fault tolerance testing"
echo "   • Interactive dashboard"
echo
echo -e "${CYAN}🔧 Available Commands:${NC}"
echo "   • View logs:    docker-compose logs -f [service]"
echo "   • Run tests:    ./test.sh"
echo "   • Stop demo:    docker-compose down"
echo "   • Cleanup:      ./cleanup.sh"
echo
echo -e "${PURPLE}📋 Service Details:${NC}"
echo "   • producer-user-events: Generates user activity data"
echo "   • producer-metrics: Generates system metrics"
echo "   • consumer-analytics: Processes analytics data"
echo "   • consumer-notifications: Handles notifications"
echo "   • consumer-recommendations: Generates recommendations"
echo "   • streaming-app: Web dashboard for monitoring"
echo
echo -e "${BLUE}💡 How to Use the Demo:${NC}"
echo "1. Open http://localhost:8080 in your browser"
echo "2. Watch real-time data flow through the pipeline"
echo "3. Monitor system metrics and performance"
echo "4. Test fault tolerance by stopping/starting services"
echo "5. View logs to understand the data processing flow"
echo
echo -e "${GREEN}🎬 Demo is now running!${NC}"
echo -e "${GREEN}Visit the dashboard to see the streaming data in action.${NC}"
echo
print_header "Happy Streaming! 🚀" 