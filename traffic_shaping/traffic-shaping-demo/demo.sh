#!/bin/bash

# Demo script for Traffic Shaping and Rate Limiting

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  🚀 Traffic Shaping and Rate Limiting Demo${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_step() {
    echo -e "${GREEN}[DEMO]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_header

print_step "Building and starting the demo environment..."
docker-compose up --build -d

print_step "Waiting for services to be ready..."
sleep 15

# Check if services are running
print_step "Checking service health..."
if curl -f http://localhost:8000/api/health > /dev/null 2>&1; then
    print_info "✓ Rate limiting service is running"
else
    echo -e "${RED}[ERROR]${NC} Service health check failed"
    exit 1
fi

print_step "Running basic functionality tests..."

# Test each rate limiter
for limiter in token_bucket sliding_window fixed_window; do
    print_info "Testing $limiter rate limiter..."
    
    # Send a few requests
    for i in {1..5}; do
        response=$(curl -s -X POST "http://localhost:8000/api/request/$limiter" \
            -H "Content-Type: application/json")
        
        allowed=$(echo "$response" | grep -o '"allowed":[^,]*' | cut -d':' -f2)
        if [ "$allowed" = "true" ]; then
            echo -e "  Request $i: ${GREEN}ALLOWED${NC}"
        else
            echo -e "  Request $i: ${RED}BLOCKED${NC}"
        fi
        
        sleep 0.5
    done
    echo
done

print_step "Running load tests..."
docker-compose run --rm load-tester

print_step "Demo is ready! Access points:"
echo -e "${BLUE}Web Dashboard:${NC} http://localhost:8000"
echo -e "${BLUE}API Docs:${NC} http://localhost:8000/docs"
echo -e "${BLUE}Health Check:${NC} http://localhost:8000/api/health"
echo

print_info "Try these manual tests:"
echo "1. Open the web dashboard and click 'Send Request' buttons"
echo "2. Run bulk tests with different parameters"
echo "3. Monitor real-time metrics and charts"
echo "4. Test API endpoints directly:"
echo "   curl -X POST http://localhost:8000/api/request/token_bucket"
echo

print_info "To stop the demo, run: ./cleanup.sh"
