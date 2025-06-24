#!/bin/bash

# Test script for zero-downtime deployments

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] $1${NC}"
}

# Test function to send requests and measure response
test_endpoint() {
    local url=$1
    local duration=${2:-10}
    local name=${3:-"Test"}
    
    log "Testing $name for ${duration}s..."
    
    if ! curl -s "$url" > /dev/null; then
        error "$name service not accessible at $url"
        return 1
    fi
    
    start_time=$(date +%s)
    end_time=$((start_time + duration))
    success_count=0
    error_count=0
    
    while [ $(date +%s) -lt $end_time ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200"; then
            success_count=$((success_count + 1))
        else
            error_count=$((error_count + 1))
        fi
        sleep 0.1
    done
    
    if [ $success_count -eq 0 ]; then
        error "$name: No successful requests"
        return 1
    fi
    
    total_requests=$((success_count + error_count))
    success_rate=$(awk "BEGIN {printf \"%.2f\", $success_count * 100 / $total_requests}")
    
    log "$name Results:"
    log "  Total Requests: $total_requests"
    log "  Success Rate: ${success_rate}%"
    log "  Errors: $error_count"
    echo
    
    return 0
}

# Test Rolling Deployment
test_rolling() {
    log "=== Testing Rolling Deployment ==="
    test_endpoint "http://localhost:8080" 30 "Rolling Deployment"
}

# Test Blue-Green Deployment
test_blue_green() {
    log "=== Testing Blue-Green Deployment ==="
    test_endpoint "http://localhost:8081" 30 "Blue-Green Deployment"
}

# Test Canary Deployment
test_canary() {
    log "=== Testing Canary Deployment ==="
    test_endpoint "http://localhost:8082" 30 "Canary Deployment"
}

# Run all tests
run_all_tests() {
    log "Starting comprehensive deployment testing..."
    
    # Check if all services are running
    warn "Checking service availability..."
    
    local tests_passed=0
    local total_tests=3
    
    if test_rolling; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_blue_green; then
        tests_passed=$((tests_passed + 1))
    fi
    
    if test_canary; then
        tests_passed=$((tests_passed + 1))
    fi
    
    log "Tests completed: $tests_passed/$total_tests passed"
    
    if [ $tests_passed -eq $total_tests ]; then
        log "🎉 All tests passed!"
    else
        warn "⚠️  Some tests failed. Check the output above for details."
    fi
}

# Load testing
load_test() {
    local url=${1:-"http://localhost:8080"}
    local concurrent=${2:-10}
    local duration=${3:-60}
    
    log "Starting load test: $concurrent concurrent users for ${duration}s"
    
    for i in $(seq 1 $concurrent); do
        (
            end_time=$(($(date +%s) + duration))
            while [ $(date +%s) -lt $end_time ]; do
                curl -s "$url" > /dev/null
                sleep 0.1
            done
        ) &
    done
    
    wait
    log "Load test completed"
}

# Main execution
case "${1:-all}" in
    "rolling")
        test_rolling
        ;;
    "blue-green")
        test_blue_green
        ;;
    "canary")
        test_canary
        ;;
    "load")
        load_test "${2:-http://localhost:8080}" "${3:-10}" "${4:-60}"
        ;;
    "all")
        run_all_tests
        ;;
    *)
        echo "Usage: $0 {rolling|blue-green|canary|load|all}"
        echo "  rolling     - Test rolling deployment"
        echo "  blue-green  - Test blue-green deployment"
        echo "  canary      - Test canary deployment"
        echo "  load [url] [concurrent] [duration] - Load test"
        echo "  all         - Run all tests"
        ;;
esac
