#!/bin/bash

# Post-Mortem Process Demo Runner
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

show_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════╗"
    echo "║       Post-Mortem Process Demo        ║"
    echo "║    Learning from System Failures      ║"
    echo "╚═══════════════════════════════════════╝"
    echo -e "${NC}"
}

check_ports() {
    if lsof -Pi :3000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port 3000 is already in use"
        echo "Please stop the service using port 3000 and try again"
        exit 1
    fi
    
    if lsof -Pi :8000 -sTCP:LISTEN -t >/dev/null 2>&1; then
        print_warning "Port 8000 is already in use"
        echo "Please stop the service using port 8000 and try again"
        exit 1
    fi
}

build_and_start() {
    print_status "Building and starting services..."
    
    # Build Docker images
    docker-compose build --no-cache
    
    # Start services
    docker-compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to start..."
    sleep 10
    
    # Check if services are running
    if ! curl -s http://localhost:8000/api/health > /dev/null; then
        print_warning "Backend service not ready, waiting..."
        sleep 15
    fi
    
    if ! curl -s http://localhost:3000 > /dev/null; then
        print_warning "Frontend service not ready, waiting..."
        sleep 10
    fi
}

run_tests() {
    print_status "Running tests..."
    
    # Test backend endpoints
    docker-compose exec -T backend npm test -- --passWithNoTests
    
    # Test frontend components
    docker-compose exec -T frontend npm test -- --passWithNoTests --watchAll=false
    
    print_success "All tests passed!"
}

show_demo_info() {
    show_banner
    
    echo -e "${GREEN}✅ Post-Mortem Management System is running!${NC}"
    echo ""
    echo "🌐 Access Points:"
    echo "   Frontend (Main UI): http://localhost:3000"
    echo "   Backend API:        http://localhost:8000/api/health"
    echo ""
    echo "🎯 Demo Features:"
    echo "   • Create and track incidents"
    echo "   • Build comprehensive post-mortems"
    echo "   • Manage action items and follow-through"
    echo "   • View analytics and learning insights"
    echo "   • Real-time collaboration features"
    echo ""
    echo "📝 Quick Test Scenarios:"
    echo "   1. Create a new incident (High severity recommended)"
    echo "   2. Build a post-mortem with timeline and root cause"
    echo "   3. Add action items with assignees and due dates"
    echo "   4. Explore the analytics dashboard"
    echo ""
    echo "🛑 To stop the demo: ./cleanup.sh"
    echo ""
    echo -e "${YELLOW}💡 Tip: Open your browser and navigate to http://localhost:3000 to begin!${NC}"
}

verify_setup() {
    print_status "Verifying setup..."
    
    # Check backend health
    local health_check=$(curl -s http://localhost:8000/api/health | jq -r .status 2>/dev/null || echo "error")
    if [ "$health_check" = "healthy" ]; then
        print_success "Backend is healthy"
    else
        print_warning "Backend health check failed"
    fi
    
    # Check frontend availability
    if curl -s http://localhost:3000 >/dev/null 2>&1; then
        print_success "Frontend is accessible"
    else
        print_warning "Frontend may not be ready yet"
    fi
    
    # Check database initialization
    local incident_count=$(curl -s http://localhost:8000/api/incidents | jq '.incidents | length' 2>/dev/null || echo "0")
    if [ "$incident_count" -gt "0" ]; then
        print_success "Database initialized with sample data"
    else
        print_warning "Database may be initializing"
    fi
}

main() {
    show_banner
    check_ports
    build_and_start
    verify_setup
    run_tests
    show_demo_info
}

# Handle script arguments
case "${1:-run}" in
    "run")
        main
        ;;
    "logs")
        docker-compose logs -f
        ;;
    "status")
        docker-compose ps
        ;;
    "restart")
        print_status "Restarting services..."
        docker-compose restart
        show_demo_info
        ;;
    *)
        echo "Usage: $0 [run|logs|status|restart]"
        exit 1
        ;;
esac
