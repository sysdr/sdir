#!/bin/bash
# ==============================================
# Start Script for Clock Skew Demo
# ==============================================
# Builds, runs, and showcases the demo behavior
# ==============================================

set -e

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$SCRIPT_DIR/skew-demo"

echo -e "${BLUE}>>> Starting Clock Skew Demo...${NC}\n"

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo -e "${RED}Error: Docker is not running. Please start Docker Desktop and try again.${NC}"
    exit 1
fi

# Check if demo directory exists, if not run setup
if [ ! -d "$DEMO_DIR" ] || [ ! -f "$DEMO_DIR/docker-compose.yml" ]; then
    echo -e "${CYAN}Demo environment not found. Running setup...${NC}"
    "$SCRIPT_DIR/setup.sh"
    echo ""
fi

# Navigate to demo directory
cd "$DEMO_DIR"

# Stop any existing containers
echo -e "${CYAN}Stopping any existing containers...${NC}"
docker-compose down > /dev/null 2>&1 || true

# Build and start containers
echo -e "${CYAN}Building and starting containers...${NC}"
docker-compose up -d --build

# Wait for services to be ready
echo -e "${CYAN}Waiting for services to start...${NC}"
sleep 3

# Check if services are running
if ! docker-compose ps | grep -q "Up"; then
    echo -e "${RED}Error: Some containers failed to start.${NC}"
    docker-compose ps
    exit 1
fi

# Display status
echo -e "\n${GREEN}>>> Demo Environment Ready! <<<${NC}\n"
echo -e "Access the dashboard at: ${BLUE}http://localhost:3000${NC}\n"

# Showcase demo behavior
echo -e "${YELLOW}=== Demo Behavior Showcase ===${NC}\n"
echo -e "${CYAN}This demo demonstrates clock skew issues in distributed systems:${NC}\n"
echo -e "1. ${GREEN}Last Write Wins (LWW)${NC} - Uses physical timestamps"
echo -e "   ${YELLOW}⚠️  Problem:${NC} If Node B's clock is slow, its writes can be rejected"
echo -e "   ${YELLOW}⚠️  Result:${NC} Data loss occurs silently\n"
echo -e "2. ${GREEN}Hybrid Logical Clock (HLC)${NC} - Combines physical time + logical counter"
echo -e "   ${GREEN}✓ Solution:${NC} Ensures timestamps always move forward"
echo -e "   ${GREEN}✓ Result:${NC} Preserves causality even during clock skew\n"

echo -e "${CYAN}How to use the demo:${NC}"
echo -e "1. Open ${BLUE}http://localhost:3000${NC} in your browser"
echo -e "2. Select a conflict resolution strategy (LWW or HLC)"
echo -e "3. Adjust the clock drift slider to skew Node B's clock (e.g., -5 seconds)"
echo -e "4. Click 'Apply Drift to Node B'"
echo -e "5. Enter some data and click 'Execute Concurrent Writes'"
echo -e "6. Observe how LWW rejects writes while HLC accepts them\n"

echo -e "${CYAN}Expected behavior:${NC}"
echo -e "• With LWW and clock skew: Node B's write will be ${RED}REJECTED${NC}"
echo -e "• With HLC and clock skew: Node B's write will be ${GREEN}ACCEPTED${NC}\n"

# Try to open browser (macOS)
if [[ "$OSTYPE" == "darwin"* ]]; then
    echo -e "${CYAN}Opening dashboard in browser...${NC}"
    open "http://localhost:3000" 2>/dev/null || true
fi

echo -e "${GREEN}Demo is running! Press Ctrl+C to stop (or run ./cleanup.sh)${NC}\n"

# Show container status
echo -e "${CYAN}Container Status:${NC}"
docker-compose ps

echo ""