#!/bin/bash

echo "========================================="
echo "SRE Dashboard Validation Script"
echo "========================================="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Test counter
PASSED=0
FAILED=0

# Function to test endpoint
test_endpoint() {
    local name=$1
    local url=$2
    local check_type=$3
    
    echo -n "Testing $name... "
    response=$(curl -s "$url")
    http_code=$(curl -s -o /dev/null -w "%{http_code}" "$url")
    
    if [ "$http_code" -ne 200 ]; then
        echo -e "${RED}FAILED${NC} (HTTP $http_code)"
        ((FAILED++))
        return 1
    fi
    
    # Check if response has data (not empty or zero values)
    case $check_type in
        "stats")
            total=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('totalServices', 0))")
            if [ "$total" -gt 0 ]; then
                echo -e "${GREEN}PASSED${NC} (Total Services: $total)"
                ((PASSED++))
            else
                echo -e "${RED}FAILED${NC} (No services)"
                ((FAILED++))
            fi
            ;;
        "array")
            count=$(echo "$response" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
            if [ "$count" -gt 0 ]; then
                echo -e "${GREEN}PASSED${NC} (Count: $count)"
                ((PASSED++))
            else
                echo -e "${YELLOW}WARNING${NC} (Empty array)"
                ((PASSED++))
            fi
            ;;
        "health")
            status=$(echo "$response" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', ''))")
            if [ "$status" = "healthy" ]; then
                echo -e "${GREEN}PASSED${NC} (Status: $status)"
                ((PASSED++))
            else
                echo -e "${RED}FAILED${NC} (Status: $status)"
                ((FAILED++))
            fi
            ;;
    esac
}

# Function to validate metric values
validate_metrics() {
    echo ""
    echo "========================================="
    echo "Validating Dashboard Metrics Values"
    echo "========================================="
    
    # Get dashboard stats
    stats=$(curl -s http://localhost:8080/api/dashboard/stats)
    
    echo "Dashboard Stats:"
    echo "$stats" | python3 -m json.tool
    
    # Extract values
    total_services=$(echo "$stats" | python3 -c "import sys, json; print(json.load(sys.stdin).get('totalServices', 0))")
    healthy_services=$(echo "$stats" | python3 -c "import sys, json; print(json.load(sys.stdin).get('healthyServices', 0))")
    active_incidents=$(echo "$stats" | python3 -c "import sys, json; print(json.load(sys.stdin).get('activeIncidents', 0))")
    error_budget=$(echo "$stats" | python3 -c "import sys, json; print(json.load(sys.stdin).get('errorBudgetHealth', 0))")
    
    echo ""
    echo "Validation Results:"
    
    # Validate total services
    if [ "$total_services" -gt 0 ]; then
        echo -e "  Total Services: ${GREEN}$total_services${NC} ✓"
    else
        echo -e "  Total Services: ${RED}$total_services${NC} ✗"
        ((FAILED++))
    fi
    
    # Validate healthy services
    if [ "$healthy_services" -gt 0 ]; then
        echo -e "  Healthy Services: ${GREEN}$healthy_services${NC} ✓"
    else
        echo -e "  Healthy Services: ${YELLOW}$healthy_services${NC} ⚠"
    fi
    
    # Validate error budget (should be between 0 and 100)
    if (( $(echo "$error_budget > 0 && $error_budget <= 100" | bc -l) )); then
        echo -e "  Error Budget Health: ${GREEN}${error_budget}%${NC} ✓"
    else
        echo -e "  Error Budget Health: ${RED}${error_budget}%${NC} ✗"
        ((FAILED++))
    fi
}

# Function to validate SLO metrics
validate_slo_metrics() {
    echo ""
    echo "========================================="
    echo "Validating SLO Metrics"
    echo "========================================="
    
    slo_data=$(curl -s http://localhost:8080/api/slo/metrics)
    count=$(echo "$slo_data" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
    
    if [ "$count" -gt 0 ]; then
        echo -e "SLO Data Points: ${GREEN}$count${NC} ✓"
        
        # Get first data point
        first_point=$(echo "$slo_data" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d[0]) if d else '{}')")
        echo "Sample Data Point:"
        echo "$first_point" | python3 -m json.tool
        
        # Validate values
        availability=$(echo "$first_point" | python3 -c "import sys, json; print(json.load(sys.stdin).get('availability', 0))")
        latency=$(echo "$first_point" | python3 -c "import sys, json; print(json.load(sys.stdin).get('latency', 0))")
        error_rate=$(echo "$first_point" | python3 -c "import sys, json; print(json.load(sys.stdin).get('errorRate', 0))")
        
        echo ""
        if (( $(echo "$availability > 0" | bc -l) )); then
            echo -e "  Availability: ${GREEN}${availability}%${NC} ✓"
        else
            echo -e "  Availability: ${RED}${availability}%${NC} ✗"
            ((FAILED++))
        fi
        
        if (( $(echo "$latency > 0" | bc -l) )); then
            echo -e "  Latency: ${GREEN}${latency}ms${NC} ✓"
        else
            echo -e "  Latency: ${RED}${latency}ms${NC} ✗"
            ((FAILED++))
        fi
        
        echo -e "  Error Rate: ${GREEN}${error_rate}%${NC} ✓"
    else
        echo -e "SLO Data Points: ${RED}0${NC} ✗"
        ((FAILED++))
    fi
}

# Function to validate service health
validate_service_health() {
    echo ""
    echo "========================================="
    echo "Validating Service Health"
    echo "========================================="
    
    services=$(curl -s http://localhost:8080/api/services/health)
    count=$(echo "$services" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))")
    
    echo "Total Services: $count"
    echo ""
    
    # Parse and display each service
    for i in $(seq 0 $((count - 1))); do
        service=$(echo "$services" | python3 -c "import sys, json; d=json.load(sys.stdin); print(json.dumps(d[$i]) if len(d) > $i else '{}')")
        
        name=$(echo "$service" | python3 -c "import sys, json; print(json.load(sys.stdin).get('name', 'Unknown'))")
        status=$(echo "$service" | python3 -c "import sys, json; print(json.load(sys.stdin).get('status', 'unknown'))")
        uptime=$(echo "$service" | python3 -c "import sys, json; print(json.load(sys.stdin).get('uptime', 0))")
        latency=$(echo "$service" | python3 -c "import sys, json; print(json.load(sys.stdin).get('latency', 0))")
        
        case $status in
            "healthy")
                echo -e "  ${GREEN}✓${NC} $name: $status (Uptime: ${uptime}%, Latency: ${latency}ms)"
                ;;
            "warning")
                echo -e "  ${YELLOW}⚠${NC} $name: $status (Uptime: ${uptime}%, Latency: ${latency}ms)"
                ;;
            "critical")
                echo -e "  ${RED}✗${NC} $name: $status (Uptime: ${uptime}%, Latency: ${latency}ms)"
                ;;
            *)
                echo -e "  ${RED}?${NC} $name: $status (Uptime: ${uptime}%, Latency: ${latency}ms)"
                ;;
        esac
    done
}

# Run tests
echo "========================================="
echo "API Endpoint Tests"
echo "========================================="
test_endpoint "Backend Health" "http://localhost:8080/health" "health"
test_endpoint "Dashboard Stats" "http://localhost:8080/api/dashboard/stats" "stats"
test_endpoint "SLO Metrics" "http://localhost:8080/api/slo/metrics" "array"
test_endpoint "Error Budget" "http://localhost:8080/api/error-budget" "array"
test_endpoint "Service Health" "http://localhost:8080/api/services/health" "array"
test_endpoint "Alerts" "http://localhost:8080/api/alerts" "array"
test_endpoint "Incidents" "http://localhost:8080/api/incidents" "array"
echo -n "Testing Frontend... "
frontend_code=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
if [ "$frontend_code" -eq 200 ]; then
    echo -e "${GREEN}PASSED${NC} (HTTP $frontend_code)"
    ((PASSED++))
else
    echo -e "${RED}FAILED${NC} (HTTP $frontend_code)"
    ((FAILED++))
fi

# Validate metrics
validate_metrics
validate_slo_metrics
validate_service_health

# Summary
echo ""
echo "========================================="
echo "Test Summary"
echo "========================================="
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    echo ""
    echo "Dashboard URL: http://localhost:3000"
    echo "Backend API: http://localhost:8080"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi

