#!/bin/bash

# IAM Dashboard - Metrics and Status Monitor
# Displays real-time metrics and validates all systems are working

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

AUTH_SERVER="http://localhost:3001"
RESOURCE_SERVER="http://localhost:3002"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

clear || true
echo "=========================================="
echo "  IAM System Dashboard"
echo "=========================================="
echo ""

# Service Health Status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Service Health"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_health() {
    local service=$1
    local url=$2
    local response=$(curl -s -w "\n%{http_code}" "$url/health" 2>/dev/null || echo -e "\n000")
    local body=$(echo "$response" | head -n -1)
    local code=$(echo "$response" | tail -n 1)
    
    if [ "$code" = "200" ]; then
        echo -e "${GREEN}✓${NC} $service: ${GREEN}HEALTHY${NC}"
        echo "  Response: $body" | python3 -m json.tool 2>/dev/null | sed 's/^/  /' || echo "  $body"
        return 0
    else
        echo -e "${RED}✗${NC} $service: ${RED}UNHEALTHY${NC} (HTTP $code)"
        return 1
    fi
}

AUTH_HEALTH=$(check_health "Auth Server" "$AUTH_SERVER")
RESOURCE_HEALTH=$(check_health "Resource Server" "$RESOURCE_SERVER")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🐳 Docker Container Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if command -v docker &> /dev/null; then
    if docker compose ps 2>/dev/null | grep -q "iam-demo"; then
        docker compose ps 2>/dev/null | grep "iam-demo" | while read line; do
            if echo "$line" | grep -q "Up"; then
                echo -e "${GREEN}✓${NC} $(echo $line | awk '{print $1 " - " $4 " - " $5 " " $6}')"
            else
                echo -e "${RED}✗${NC} $(echo $line | awk '{print $1 " - " $4}')"
            fi
        done
    else
        # Try docker-compose
        docker-compose ps 2>/dev/null | grep "iam-demo" | while read line; do
            if echo "$line" | grep -q "Up"; then
                echo -e "${GREEN}✓${NC} $(echo $line | awk '{print $1 " - " $4 " - " $5 " " $6}')"
            else
                echo -e "${RED}✗${NC} $(echo $line | awk '{print $1 " - " $4}')"
            fi
        done
    fi
else
    echo -e "${YELLOW}⚠${NC} Docker command not available"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📈 System Metrics"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Test OAuth Flow and Collect Metrics
METRICS_OK=0
METRICS_TOTAL=0

test_endpoint() {
    local name=$1
    local method=$2
    local url=$3
    local headers=$4
    local data=$5
    
    METRICS_TOTAL=$((METRICS_TOTAL + 1))
    
    if [ "$method" = "GET" ]; then
        response=$(curl -s -w "\n%{http_code}" $headers "$url" 2>/dev/null || echo -e "\n000")
    else
        response=$(curl -s -w "\n%{http_code}" -X "$method" $headers -d "$data" "$url" 2>/dev/null || echo -e "\n000")
    fi
    
    http_code=$(echo "$response" | tail -n 1)
    body=$(echo "$response" | head -n -1)
    
    if [ "$http_code" = "200" ] || [ "$http_code" = "201" ]; then
        echo -e "${GREEN}✓${NC} $name: ${GREEN}WORKING${NC} (HTTP $http_code)"
        METRICS_OK=$((METRICS_OK + 1))
        
        # Try to extract meaningful data
        if echo "$body" | grep -q "access_token\|documents\|message\|token"; then
            echo -e "  ${BLUE}Data returned: Yes${NC}"
        fi
        return 0
    else
        echo -e "${RED}✗${NC} $name: ${RED}FAILED${NC} (HTTP $http_code)"
        return 1
    fi
}

# Test 1: Public Endpoint
echo ""
test_endpoint "Public Endpoint" "GET" "$RESOURCE_SERVER/api/public/info" ""

# Test 2: OAuth Authorization (may not work in automated test, but we try)
echo ""
AUTH_RESPONSE=$(curl -s "$AUTH_SERVER/oauth/authorize?client_id=demo-client&redirect_uri=http://localhost:8080/callback&response_type=code&scope=read&state=test123" 2>/dev/null || echo "")
if echo "$AUTH_RESPONSE" | grep -q "redirect_to\|Authorization successful"; then
    echo -e "${GREEN}✓${NC} OAuth Authorization Endpoint: ${GREEN}WORKING${NC}"
    METRICS_OK=$((METRICS_OK + 1))
else
    echo -e "${YELLOW}⚠${NC} OAuth Authorization Endpoint: ${YELLOW}NEEDS MANUAL TEST${NC}"
fi
METRICS_TOTAL=$((METRICS_TOTAL + 1))

# Test 3: Health endpoints
echo ""
test_endpoint "Auth Server Health" "GET" "$AUTH_SERVER/health" ""
test_endpoint "Resource Server Health" "GET" "$RESOURCE_SERVER/health" ""

# Database Connection Check (indirect - via service health)
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💾 Database & Cache Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if we can connect to postgres (via docker)
if command -v docker &> /dev/null; then
    POSTGRES_CONTAINER=$(docker ps --filter "name=postgres" --format "{{.Names}}" | grep -i iam 2>/dev/null | head -1)
    if [ ! -z "$POSTGRES_CONTAINER" ]; then
        if docker exec "$POSTGRES_CONTAINER" pg_isready -U iam_user -d iam_db >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} PostgreSQL: ${GREEN}CONNECTED${NC}"
        else
            echo -e "${YELLOW}⚠${NC} PostgreSQL: ${YELLOW}CONTAINER RUNNING BUT NOT READY${NC}"
        fi
    else
        echo -e "${RED}✗${NC} PostgreSQL: ${RED}CONTAINER NOT FOUND${NC}"
    fi
    
    REDIS_CONTAINER=$(docker ps --filter "name=redis" --format "{{.Names}}" | grep -i iam 2>/dev/null | head -1)
    if [ ! -z "$REDIS_CONTAINER" ]; then
        if docker exec "$REDIS_CONTAINER" redis-cli ping >/dev/null 2>&1; then
            echo -e "${GREEN}✓${NC} Redis: ${GREEN}CONNECTED${NC}"
        else
            echo -e "${YELLOW}⚠${NC} Redis: ${YELLOW}CONTAINER RUNNING BUT NOT READY${NC}"
        fi
    else
        echo -e "${RED}✗${NC} Redis: ${RED}CONTAINER NOT FOUND${NC}"
    fi
fi

# Port Status
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔌 Port Status"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

check_port() {
    local port=$1
    local service=$2
    
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1 || \
       netstat -tuln 2>/dev/null | grep -q ":$port " || \
       ss -tuln 2>/dev/null | grep -q ":$port "; then
        echo -e "${GREEN}✓${NC} Port $port ($service): ${GREEN}IN USE${NC}"
    else
        echo -e "${RED}✗${NC} Port $port ($service): ${RED}NOT IN USE${NC}"
    fi
}

check_port 3001 "Auth Server"
check_port 3002 "Resource Server"
check_port 5432 "PostgreSQL"
check_port 6379 "Redis"

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $METRICS_TOTAL -gt 0 ]; then
    PERCENTAGE=$((METRICS_OK * 100 / METRICS_TOTAL))
    echo "Metrics Status: $METRICS_OK/$METRICS_TOTAL tests passing ($PERCENTAGE%)"
    
    if [ $PERCENTAGE -eq 100 ]; then
        echo -e "Overall Status: ${GREEN}✓ ALL SYSTEMS OPERATIONAL${NC}"
    elif [ $PERCENTAGE -ge 50 ]; then
        echo -e "Overall Status: ${YELLOW}⚠ PARTIAL OPERATION${NC}"
    else
        echo -e "Overall Status: ${RED}✗ SYSTEM ISSUES DETECTED${NC}"
    fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Next Steps"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  • Run './demo.sh' to execute full OAuth flow"
echo "  • Run './dashboard.sh' again to refresh metrics"
echo "  • Check logs: docker-compose logs -f"
echo ""

