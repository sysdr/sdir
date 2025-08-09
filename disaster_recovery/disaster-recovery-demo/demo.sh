#!/bin/bash

# Main demo script for disaster recovery planning
# This script builds, runs, tests, and demonstrates the complete system

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[DEMO] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[DEMO] $1${NC}"
}

error() {
    echo -e "${RED}[DEMO] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[DEMO] $1${NC}"
}

# Build all services
build_services() {
    log "Building all disaster recovery services..."
    
    docker-compose build --no-cache
    
    log "All services built successfully"
}

# Start all services
start_services() {
    log "Starting disaster recovery demo environment..."
    
    docker-compose up -d
    
    log "Services starting... This may take a few moments."
    
    # Wait for critical services to be healthy
    log "Waiting for services to become healthy..."
    
    local max_attempts=30
    local attempt=1
    
    while [ $attempt -le $max_attempts ]; do
        if docker-compose ps | grep -q "Up"; then
            if curl -sf http://localhost:3000/health > /dev/null 2>&1; then
                log "✓ Dashboard is ready"
                break
            fi
        fi
        
        info "Waiting for services... ($attempt/$max_attempts)"
        sleep 10
        attempt=$((attempt + 1))
    done
    
    if [ $attempt -gt $max_attempts ]; then
        error "Services did not start within expected time"
    fi
}

# Show service status
show_status() {
    log "Current service status:"
    docker-compose ps
    
    echo ""
    log "Service URLs:"
    log "🌐 Main Dashboard: http://localhost:3000"
    log "💳 Payment Service: http://localhost:3001/health"
    log "📦 Inventory Service: http://localhost:3002/health"  
    log "📊 Analytics Service: http://localhost:3003/health"
    
    echo ""
    log "Database Status:"
    log "🔴 Redis (Tier 1): localhost:6379"
    log "🟢 PostgreSQL (Tier 2): localhost:5432"
    log "🟡 InfluxDB (Tier 3): localhost:8086"
}

# Run comprehensive tests
run_tests() {
    log "Running comprehensive disaster recovery tests..."
    
    if [ -f "./test-disaster-recovery.sh" ]; then
        ./test-disaster-recovery.sh
    else
        error "Test script not found. Please run the complete setup first."
    fi
}

# Display demo instructions
show_demo_instructions() {
    echo ""
    log "=========================================="
    log "🚨 DISASTER RECOVERY DEMO IS READY! 🚨"
    log "=========================================="
    echo ""
    
    info "LEARNING OBJECTIVES:"
    info "• Understand RTO (Recovery Time Objective) and RPO (Recovery Point Objective)"
    info "• Experience multi-tier service recovery strategies"
    info "• Test disaster simulation and recovery procedures"
    info "• Monitor real-time recovery metrics and compliance"
    echo ""
    
    info "DEMO ACTIVITIES:"
    info "1. 🌐 EXPLORE DASHBOARD"
    info "   → Open: http://localhost:3000"
    info "   → View service health status across all tiers"
    info "   → Observe RTO/RPO objectives for each service"
    echo ""
    
    info "2. 💥 SIMULATE DISASTERS"
    info "   → Use the disaster simulation buttons on the dashboard"
    info "   → Test Tier 1 (Payment): RTO=30s, RPO=0s"
    info "   → Test Tier 2 (Inventory): RTO=5min, RPO=1min"  
    info "   → Test Tier 3 (Analytics): RTO=4hr, RPO=1hr"
    echo ""
    
    info "3. 📊 MONITOR RECOVERY"
    info "   → Watch real-time recovery progress"
    info "   → Compare actual vs expected recovery times"
    info "   → Observe automatic service restoration"
    echo ""
    
    info "4. 🧪 MANUAL TESTING"
    info "   → Process payments during disasters"
    info "   → Update inventory during recovery"
    info "   → Generate analytics events"
    echo ""
    
    info "SAMPLE API CALLS:"
    info "# Process Payment (Tier 1)"
    info 'curl -X POST http://localhost:3001/payment/process \'
    info '  -H "Content-Type: application/json" \'
    info '  -d '"'"'{"customerId":"demo-user","amount":99.99}'"'"
    echo ""
    
    info "# Update Inventory (Tier 2)"
    info 'curl -X PUT http://localhost:3002/inventory/1 \'
    info '  -H "Content-Type: application/json" \'  
    info '  -d '"'"'{"quantity":200}'"'"
    echo ""
    
    info "# Send Analytics Event (Tier 3)"
    info 'curl -X POST http://localhost:3003/analytics/event \'
    info '  -H "Content-Type: application/json" \'
    info '  -d '"'"'{"eventType":"demo_event","userId":"demo-user"}'"'"
    echo ""
    
    info "LOGS AND MONITORING:"
    info "• View service logs: docker-compose logs [service-name]"
    info "• Monitor all logs: docker-compose logs -f"
    info "• Check container status: docker-compose ps"
    echo ""
    
    info "CLEANUP:"
    info "• Stop demo: docker-compose down"
    info "• Complete cleanup: ./cleanup.sh"
    echo ""
    
    log "🎯 KEY LEARNING: Notice how different tiers have different recovery strategies!"
    log "• Tier 1: Immediate recovery with no data loss"
    log "• Tier 2: Quick recovery with minimal data loss"
    log "• Tier 3: Longer recovery with acceptable data loss"
    echo ""
}

# Main demo execution
main() {
    log "🚀 Starting Disaster Recovery Planning Demo"
    log "===========================================" 
    
    # Build services
    build_services
    
    # Start services
    start_services
    
    # Show status
    show_status
    
    # Run tests
    run_tests
    
    # Show demo instructions
    show_demo_instructions
    
    log "Demo initialization complete! Happy learning! 🎓"
}

main "$@"
