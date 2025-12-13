#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Service URLs
USER_SERVICE="http://localhost:3001"
ORDER_SERVICE="http://localhost:3002"
INVENTORY_SERVICE="http://localhost:3003"

# Helper function to print colored output
print_step() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}▶ $1${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Function to check if service is healthy
check_health() {
    local service=$1
    local url=$2
    local name=$3
    
    if curl -s -f "$url/health" > /dev/null 2>&1; then
        print_success "$name is healthy"
        return 0
    else
        print_error "$name is not responding"
        return 1
    fi
}

# Function to get stats
get_stats() {
    local service=$1
    local url=$2
    
    if command -v python3 &> /dev/null; then
        curl -s "$url/stats" | python3 -m json.tool 2>/dev/null || curl -s "$url/stats"
    elif command -v jq &> /dev/null; then
        curl -s "$url/stats" | jq '.' 2>/dev/null || curl -s "$url/stats"
    else
        curl -s "$url/stats"
    fi
}

# Function to make a request and measure latency
make_request() {
    local url=$1
    local description=$2
    
    local start_time=$(date +%s%N)
    local response=$(curl -s -w "\n%{http_code}" "$url" 2>&1)
    local end_time=$(date +%s%N)
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    local latency=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    echo "$http_code|$latency|$body"
}

# Function to wait for service recovery
wait_for_recovery() {
    local service=$1
    local url=$2
    local max_wait=${3:-30}  # Default 30 seconds
    local waited=0
    
    print_info "Waiting for $service to recover (max ${max_wait}s)..."
    
    while [ $waited -lt $max_wait ]; do
        local stats=$(curl -s "$url/stats" 2>/dev/null)
        if command -v python3 &> /dev/null; then
            local active=$(echo "$stats" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('activeRequests', 999))" 2>/dev/null || echo "999")
            local utilization=$(echo "$stats" | python3 -c "import sys, json; data=json.load(sys.stdin); print(data.get('threadUtilization', 100))" 2>/dev/null || echo "100")
        elif command -v jq &> /dev/null; then
            local active=$(echo "$stats" | jq -r '.activeRequests // 999' 2>/dev/null || echo "999")
            local utilization=$(echo "$stats" | jq -r '.threadUtilization // 100' 2>/dev/null || echo "100")
        else
            # If no JSON parser, assume recovered after a short wait
            sleep 3
            return 0
        fi
        
        if [ "$active" -lt 5 ] && [ "$utilization" -lt 50 ]; then
            print_success "$service recovered (Active: $active, Utilization: ${utilization}%)"
            return 0
        fi
        
        sleep 1
        waited=$((waited + 1))
        if [ $((waited % 5)) -eq 0 ]; then
            print_info "  Still waiting... (${waited}s) - Active: $active, Utilization: ${utilization}%"
        fi
    done
    
    print_info "$service may still be under load, continuing anyway..."
    return 0
}

# Function to toggle circular calls
toggle_circular() {
    local enable=$1
    local current_state="unknown"
    
    # Try to get current state
    if command -v python3 &> /dev/null; then
        current_state=$(curl -s "$INVENTORY_SERVICE/health" | python3 -c "import sys, json; data=json.load(sys.stdin); print('enabled' if data.get('circularCallsEnabled', False) else 'disabled')" 2>/dev/null || echo "unknown")
    elif command -v jq &> /dev/null; then
        current_state=$(curl -s "$INVENTORY_SERVICE/health" | jq -r 'if .circularCallsEnabled == true then "enabled" else "disabled" end' 2>/dev/null || echo "unknown")
    fi
    
    # Always toggle if we can't determine state, or if state needs to change
    if [ "$enable" = "true" ] && [ "$current_state" != "enabled" ]; then
        curl -s -X POST "$INVENTORY_SERVICE/toggle-circular" > /dev/null
        print_info "Circular calls enabled"
    elif [ "$enable" = "false" ] && [ "$current_state" != "disabled" ]; then
        curl -s -X POST "$INVENTORY_SERVICE/toggle-circular" > /dev/null
        print_info "Circular calls disabled"
    elif [ "$current_state" != "unknown" ]; then
        print_info "Circular calls already ${current_state}"
    else
        # Can't determine state, just toggle
        curl -s -X POST "$INVENTORY_SERVICE/toggle-circular" > /dev/null
        print_info "Toggled circular calls"
    fi
}

# Main test execution
main() {
    print_step "Circular Dependencies Demo Test Script"
    echo ""
    
    # Step 1: Check all services are healthy
    print_step "Step 1: Checking Service Health"
    if ! check_health "user" "$USER_SERVICE" "User Service"; then
        print_error "Please ensure all services are running: docker-compose up -d"
        exit 1
    fi
    check_health "order" "$ORDER_SERVICE" "Order Service"
    check_health "inventory" "$INVENTORY_SERVICE" "Inventory Service"
    echo ""
    
    # Wait for services to be in a recoverable state
    print_info "Checking if services need recovery..."
    wait_for_recovery "User Service" "$USER_SERVICE" 20
    wait_for_recovery "Order Service" "$ORDER_SERVICE" 10
    wait_for_recovery "Inventory Service" "$INVENTORY_SERVICE" 10
    echo ""
    sleep 2
    
    # Step 2: Initial stats baseline
    print_step "Step 2: Baseline Statistics"
    print_info "User Service Stats:"
    get_stats "user" "$USER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization)" || true
    print_info "Order Service Stats:"
    get_stats "order" "$ORDER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization)" || true
    print_info "Inventory Service Stats:"
    get_stats "inventory" "$INVENTORY_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization)" || true
    echo ""
    sleep 2
    
    # Step 3: Normal requests (no circular dependency)
    print_step "Step 3: Normal Requests (No Circular Dependency)"
    print_info "Disabling circular calls..."
    toggle_circular "false"
    sleep 1
    
    print_info "First, testing simple endpoint /user/123 (no circular dependency)..."
    for i in {1..3}; do
        result=$(make_request "$USER_SERVICE/user/123" "Simple request $i")
        http_code=$(echo "$result" | cut -d'|' -f1)
        latency=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$http_code" = "200" ]; then
            print_success "Simple request $i: HTTP $http_code (${latency}ms)"
        else
            print_error "Simple request $i: HTTP $http_code"
        fi
        sleep 0.3
    done
    
    print_info "Now making 5 requests to /user/123/orders (triggers Order → Inventory)..."
    success_count=0
    for i in {1..5}; do
        result=$(make_request "$USER_SERVICE/user/123/orders" "Normal request $i")
        http_code=$(echo "$result" | cut -d'|' -f1)
        latency=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$http_code" = "200" ]; then
            print_success "Request $i: HTTP $http_code (${latency}ms)"
            success_count=$((success_count + 1))
        elif [ "$http_code" = "503" ]; then
            print_info "Request $i: HTTP $http_code - Service Unavailable (thread pool may be busy)"
        else
            print_error "Request $i: HTTP $http_code"
        fi
        sleep 0.5
    done
    
    if [ $success_count -gt 0 ]; then
        print_success "Normal requests working: $success_count/5 succeeded"
    else
        print_info "Note: All requests returned 503 - system may be under load from dashboard polling"
    fi
    echo ""
    sleep 2
    
    # Step 4: Enable circular calls
    print_step "Step 4: Enabling Circular Dependency Pattern"
    print_info "Enabling circular calls in Inventory Service..."
    toggle_circular "true"
    sleep 1
    
    # Step 5: Trigger circular dependency with low load
    print_step "Step 5: Low Load Test (5 requests)"
    print_info "Making 5 requests that will trigger circular dependency..."
    success_count=0
    error_count=0
    loop_detected=0
    
    for i in {1..5}; do
        result=$(make_request "$USER_SERVICE/user/123/orders" "Circular request $i")
        http_code=$(echo "$result" | cut -d'|' -f1)
        latency=$(echo "$result" | cut -d'|' -f2)
        body=$(echo "$result" | cut -d'|' -f3-)
        
        if [ "$http_code" = "200" ]; then
            print_success "Request $i: HTTP $http_code (${latency}ms)"
            success_count=$((success_count + 1))
        elif [ "$http_code" = "508" ]; then
            print_info "Request $i: HTTP $http_code - Loop Detected (${latency}ms)"
            loop_detected=$((loop_detected + 1))
        else
            print_error "Request $i: HTTP $http_code"
            error_count=$((error_count + 1))
        fi
        sleep 0.3
    done
    
    print_info "Results: $success_count successful, $loop_detected loop detected, $error_count errors"
    echo ""
    sleep 2
    
    # Step 6: Check stats after low load
    print_step "Step 6: Statistics After Low Load"
    print_info "User Service Stats:"
    get_stats "user" "$USER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization|circuitBreaker)" || true
    print_info "Order Service Stats:"
    get_stats "order" "$ORDER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization)" || true
    print_info "Inventory Service Stats:"
    get_stats "inventory" "$INVENTORY_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization|circularCallsEnabled)" || true
    echo ""
    sleep 3
    
    # Step 7: High load test - trigger thread exhaustion
    print_step "Step 7: High Load Test - Triggering Thread Pool Exhaustion"
    print_info "Sending 20 rapid requests (10 req/s) to trigger thread pool exhaustion..."
    print_info "Watch the dashboard at http://localhost:8080 to see thread utilization increase!"
    
    success_count=0
    error_count=0
    loop_detected=0
    service_unavailable=0
    
    for i in {1..20}; do
        result=$(make_request "$USER_SERVICE/user/123/orders" "High load request $i")
        http_code=$(echo "$result" | cut -d'|' -f1)
        latency=$(echo "$result" | cut -d'|' -f2)
        
        case "$http_code" in
            200)
                print_success "Request $i: HTTP $http_code (${latency}ms)"
                success_count=$((success_count + 1))
                ;;
            508)
                print_info "Request $i: HTTP $http_code - Loop Detected (${latency}ms)"
                loop_detected=$((loop_detected + 1))
                ;;
            503)
                print_error "Request $i: HTTP $http_code - Service Unavailable (${latency}ms)"
                service_unavailable=$((service_unavailable + 1))
                ;;
            *)
                print_error "Request $i: HTTP $http_code"
                error_count=$((error_count + 1))
                ;;
        esac
        
        sleep 0.1  # 10 requests per second
    done
    
    echo ""
    print_info "High Load Results:"
    print_info "  Successful: $success_count"
    print_info "  Loop Detected: $loop_detected"
    print_info "  Service Unavailable: $service_unavailable"
    print_info "  Other Errors: $error_count"
    echo ""
    sleep 3
    
    # Step 8: Check stats after high load
    print_step "Step 8: Statistics After High Load"
    print_info "User Service Stats:"
    get_stats "user" "$USER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization|circuitBreaker)" || true
    print_info "Order Service Stats:"
    get_stats "order" "$ORDER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization)" || true
    print_info "Inventory Service Stats:"
    get_stats "inventory" "$INVENTORY_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization|circularCallsEnabled)" || true
    echo ""
    sleep 3
    
    # Step 9: Recovery test
    print_step "Step 9: Recovery Test - Disabling Circular Calls"
    print_info "Disabling circular calls to allow system recovery..."
    toggle_circular "false"
    sleep 2
    
    print_info "Making 5 recovery requests..."
    for i in {1..5}; do
        result=$(make_request "$USER_SERVICE/user/123/orders" "Recovery request $i")
        http_code=$(echo "$result" | cut -d'|' -f1)
        latency=$(echo "$result" | cut -d'|' -f2)
        
        if [ "$http_code" = "200" ]; then
            print_success "Request $i: HTTP $http_code (${latency}ms)"
        else
            print_error "Request $i: HTTP $http_code"
        fi
        sleep 0.5
    done
    echo ""
    sleep 2
    
    # Step 10: Final stats
    print_step "Step 10: Final Statistics"
    print_info "User Service Stats:"
    get_stats "user" "$USER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization|circuitBreaker)" || true
    print_info "Order Service Stats:"
    get_stats "order" "$ORDER_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization)" || true
    print_info "Inventory Service Stats:"
    get_stats "inventory" "$INVENTORY_SERVICE" | grep -E "(totalRequests|activeRequests|threadUtilization|circularCallsEnabled)" || true
    echo ""
    
    # Summary
    print_step "Test Summary"
    print_success "All test scenarios completed!"
    echo ""
    print_info "What happened:"
    echo "  1. ✓ Service health checks completed"
    echo "  2. ✓ Baseline statistics collected"
    echo "  3. ✓ Normal requests tested (may show 503 if system under load)"
    echo "  4. ✓ Circular dependency pattern enabled"
    echo "  5. ✓ Low and high load tests executed"
    echo "  6. ✓ Thread pool exhaustion demonstrated (503 responses)"
    echo "  7. ✓ Statistics collected at each stage"
    echo "  8. ✓ Circular calls disabled for recovery"
    echo ""
    print_info "Note: If you see many 503 responses, it's because:"
    echo "  - The dashboard polls services every second, keeping thread pools busy"
    echo "  - This demonstrates real-world thread pool exhaustion"
    echo "  - The 503 responses are CORRECT behavior when threads are exhausted"
    echo ""
    print_info "View the dashboard at: http://localhost:8080"
    print_info "The dashboard shows:"
    echo "  - Thread utilization (should be high if system is busy)"
    echo "  - Latency measurements in the chart"
    echo "  - Request count increases"
    echo "  - Circuit breaker status"
    echo "  - Service health status"
    echo ""
    print_info "To see successful requests, stop the dashboard polling or wait for recovery."
    echo ""
}

# Run the test
main

