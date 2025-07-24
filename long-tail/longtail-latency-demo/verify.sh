#!/bin/bash

# Long-tail Latency Observatory - Verification and Learning Guide
# System Design Interview Roadmap - Issue #105

set -e

PROJECT_NAME="longtail-latency-demo"
PROJECT_DIR=$(pwd)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}================================${NC}"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_insight() {
    echo -e "${MAGENTA}[INSIGHT]${NC} $1"
}

wait_for_service() {
    local max_wait=60
    local counter=0
    
    print_step "Waiting for service to be ready (max ${max_wait}s)..."
    
    while [ $counter -lt $max_wait ]; do
        if curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
            print_success "Service is ready!"
            return 0
        fi
        sleep 1
        counter=$((counter + 1))
        if [ $((counter % 10)) -eq 0 ]; then
            echo -n "⏳ Still waiting... (${counter}s) "
        fi
    done
    
    echo ""
    echo "❌ Service failed to start within $max_wait seconds"
    echo "Check Docker logs with: docker-compose logs"
    return 1
}

verify_endpoints() {
    print_header "API ENDPOINT VERIFICATION"
    
    local endpoints=(
        "/api/health:Health Check"
        "/api/config:Configuration"
        "/api/metrics:Metrics Collection"
        "/api/simulate:Request Simulation"
    )
    
    for endpoint_info in "${endpoints[@]}"; do
        IFS=':' read -r endpoint description <<< "$endpoint_info"
        
        print_step "Testing $description ($endpoint)..."
        
        if response=$(curl -s "http://localhost:8000$endpoint"); then
            if echo "$response" | python3 -m json.tool > /dev/null 2>&1; then
                print_success "$description endpoint working"
            else
                echo "⚠️  $description returned non-JSON response"
            fi
        else
            echo "❌ $description endpoint failed"
            return 1
        fi
    done
    
    print_success "All API endpoints verified!"
}

demonstrate_latency_sources() {
    print_header "LATENCY SOURCES DEMONSTRATION"
    
    print_step "Testing baseline performance..."
    baseline=$(curl -s http://localhost:8000/api/simulate | python3 -c "import sys,json; print(json.load(sys.stdin)['response_time_ms'])")
    print_warning "Baseline latency: ${baseline}ms"
    
    # Enable GC pauses
    print_step "Enabling GC pause simulation..."
    curl -s -X POST http://localhost:8000/api/config \
        -H "Content-Type: application/json" \
        -d '{"gc_pause_enabled": true, "gc_pause_probability": 0.5, "gc_pause_duration": 200}' > /dev/null
    
    print_step "Testing with GC pauses (may take a moment)..."
    for i in {1..5}; do
        response=$(curl -s http://localhost:8000/api/simulate)
        latency=$(echo "$response" | python3 -c "import sys,json; print(json.load(sys.stdin)['response_time_ms'])")
        sources=$(echo "$response" | python3 -c "import sys,json; data=json.load(sys.stdin); print(', '.join(data.get('latency_sources', [])))")
        
        if [ "$sources" != "" ]; then
            print_insight "Request $i: ${latency}ms (Sources: $sources)"
        else
            print_warning "Request $i: ${latency}ms (No latency sources)"
        fi
    done
    
    # Reset configuration
    curl -s -X POST http://localhost:8000/api/config \
        -H "Content-Type: application/json" \
        -d '{"gc_pause_enabled": false}' > /dev/null
    
    print_success "Latency sources demonstration completed!"
}

interactive_learning_guide() {
    print_header "INTERACTIVE LEARNING GUIDE"
    
    echo "🎓 Welcome to the Long-tail Latency Observatory!"
    echo ""
    echo "This demo teaches critical concepts about latency in distributed systems:"
    echo ""
    echo "1. 📊 DASHBOARD ACCESS:"
    echo "   • Open: http://localhost:8000"
    echo "   • Real-time latency percentile charts"
    echo "   • Live system metrics and configuration"
    echo ""
    echo "2. 🧪 EXPERIMENTS TO TRY:"
    echo "   • Enable 'GC Pauses' and watch P99 latency spike"
    echo "   • Turn on 'DB Lock Contention' to see blocking effects"
    echo "   • Test 'Load Shedding' under heavy load"
    echo "   • Compare 'Request Hedging' effectiveness"
    echo ""
    echo "3. 🎯 KEY INSIGHTS TO DISCOVER:"
    print_insight "P50 vs P99: Why averages lie about user experience"
    print_insight "Latency Sources: How multiple causes compound"
    print_insight "Mitigation Trade-offs: Performance vs complexity"
    print_insight "System Behavior: How tail latency affects scaling"
    echo ""
    echo "4. 🔬 ADVANCED EXPERIMENTS:"
    echo "   • Run concurrent load tests with different intensities"
    echo "   • Observe circuit breaker state transitions"
    echo "   • Monitor system resource correlation with latency"
    echo "   • Test combinations of multiple latency sources"
    echo ""
    echo "5. 📚 PRODUCTION RELEVANCE:"
    print_insight "Real systems exhibit these exact patterns"
    print_insight "P99 latency often drives user satisfaction more than P50"
    print_insight "Mitigation strategies must be chosen based on workload"
    print_insight "Observability is crucial for diagnosing tail latency"
    echo ""
}

main() {
    echo "🔍 Long-tail Latency Observatory - Verification Guide"
    echo "===================================================="
    echo ""
    
    # Check if service is running
    if ! curl -s http://localhost:8000/api/health > /dev/null 2>&1; then
        echo "⚠️  Service doesn't appear to be running."
        echo "Start it first with: docker-compose up -d"
        echo "Or run the main demo script: ./demo.sh"
        exit 1
    fi
    
    wait_for_service || exit 1
    verify_endpoints || exit 1
    demonstrate_latency_sources
    interactive_learning_guide
    
    print_success "🎉 System verification completed successfully!"
    echo ""
    echo "📊 Dashboard ready at: http://localhost:8000"
    echo "🧪 Run './test.sh' for additional tests"
    echo "🧹 Run './cleanup.sh' when finished"
}

# Run main function
main "$@"
