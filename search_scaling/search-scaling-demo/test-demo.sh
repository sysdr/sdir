#!/bin/bash

# Search Scaling Demo - Test Script
# This script tests the demo environment to ensure everything is working

set -e  # Exit on any error

echo "🧪 Testing Search Scaling Demo"
echo "=============================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

# Test counter
tests_passed=0
tests_failed=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    local expected_result="$3"
    
    print_status "Running: $test_name"
    
    if eval "$test_command" > /dev/null 2>&1; then
        print_success "$test_name"
        ((tests_passed++))
        return 0
    else
        print_error "$test_name"
        ((tests_failed++))
        return 1
    fi
}

# Test Docker availability
test_docker() {
    run_test "Docker is running" "docker info" "Docker should be running"
}

# Test Docker Compose availability
test_docker_compose() {
    run_test "Docker Compose is available" "docker-compose --version" "Docker Compose should be available"
}

# Test required files exist
test_required_files() {
    local required_files=(
        "app/app.py"
        "app/templates/index.html"
        "docker-compose.yml"
        "Dockerfile"
        "requirements.txt"
        "config/init.sql"
    )
    
    for file in "${required_files[@]}"; do
        run_test "File exists: $file" "[ -f '$file' ]" "File should exist"
    done
}

# Test script permissions
test_script_permissions() {
    local scripts=("build.sh" "start-demo.sh" "simulate-load.sh" "demo.sh")
    
    for script in "${scripts[@]}"; do
        if [ -f "$script" ]; then
            run_test "Script is executable: $script" "[ -x '$script' ]" "Script should be executable"
        fi
    done
}

# Test if demo is running
test_demo_running() {
    run_test "Demo web interface is accessible" "curl -s http://localhost:5000/health" "Demo should be running"
}

# Test search functionality
test_search_functionality() {
    local search_types=("database" "elasticsearch" "cached")
    
    for search_type in "${search_types[@]}"; do
        run_test "Search type works: $search_type" "curl -s 'http://localhost:5000/search?q=test&type=$search_type&limit=5'" "Search should work"
    done
}

# Test metrics endpoint
test_metrics_endpoint() {
    run_test "Metrics endpoint is accessible" "curl -s http://localhost:5000/metrics" "Metrics should be accessible"
}

# Test service health
test_service_health() {
    local services=("elasticsearch" "redis" "postgres" "search-app")
    
    for service in "${services[@]}"; do
        run_test "Service is running: $service" "docker-compose ps $service | grep -q 'Up\|healthy'" "Service should be running"
    done
}

# Test data loading
test_data_loading() {
    run_test "Sample data is loaded" "curl -s 'http://localhost:5000/search?q=technology&type=elasticsearch&limit=1' | grep -q 'results'" "Data should be loaded"
}

# Performance test
test_performance() {
    print_status "Running performance test..."
    
    local start_time=$(date +%s%N)
    local response=$(curl -s "http://localhost:5000/search?q=technology&type=elasticsearch&limit=10")
    local end_time=$(date +%s%N)
    
    local duration=$(( (end_time - start_time) / 1000000 ))  # Convert to milliseconds
    
    if [ "$duration" -lt 5000 ]; then  # Less than 5 seconds
        print_success "Performance test passed (${duration}ms)"
        ((tests_passed++))
    else
        print_error "Performance test failed (${duration}ms - too slow)"
        ((tests_failed++))
    fi
}

# Show test results
show_results() {
    echo ""
    echo "🧪 Test Results Summary"
    echo "======================"
    echo "Tests Passed: $tests_passed"
    echo "Tests Failed: $tests_failed"
    echo "Total Tests: $((tests_passed + tests_failed))"
    echo ""
    
    if [ $tests_failed -eq 0 ]; then
        print_success "🎉 All tests passed! Demo is working correctly."
        return 0
    else
        print_error "❌ Some tests failed. Please check the issues above."
        return 1
    fi
}

# Main test function
main() {
    echo ""
    print_status "Starting comprehensive demo tests..."
    echo ""
    
    # Basic environment tests
    test_docker
    test_docker_compose
    test_required_files
    test_script_permissions
    
    echo ""
    print_status "Checking if demo is running..."
    
    # Demo functionality tests (only if demo is running)
    if curl -s http://localhost:5000/health > /dev/null 2>&1; then
        print_success "Demo is running, testing functionality..."
        echo ""
        
        test_demo_running
        test_service_health
        test_search_functionality
        test_metrics_endpoint
        test_data_loading
        test_performance
        
    else
        print_warning "Demo is not running. Start it with './start-demo.sh' to run full tests."
        echo ""
        print_status "Basic environment tests completed."
    fi
    
    show_results
}

# Run main function
main "$@" 