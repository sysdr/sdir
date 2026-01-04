#!/bin/bash

set -e

echo "🔥 Hot Key Problem in Consistent Hashing - Interactive Demo"
echo "============================================================"
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color


echo -e "${BLUE}🔨 Building Docker containers...${NC}"
docker-compose build

echo ""
echo -e "${BLUE}🚀 Starting services...${NC}"
docker-compose up -d

echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}✅ Demo is running!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}📊 Dashboard: ${NC}${GREEN}http://localhost:3000${NC}"
echo -e "${YELLOW}🔌 Backend API: ${NC}${GREEN}http://localhost:8080${NC}"
echo ""
echo -e "${BLUE}Instructions:${NC}"
echo "1. Open http://localhost:3000 in your browser"
echo "2. Watch as the celebrity user (100K QPS) crashes servers"
echo "3. Try different solutions:"
echo "   - Standard CH: See the cascade failure"
echo "   - Bounded Loads: Traffic spreads across multiple servers"
echo "   - Key Salting: Celebrity split into 4 sub-keys"
echo "   - Hot Store: Celebrity bypasses the ring entirely"
echo ""
echo -e "${YELLOW}📝 Logs:${NC} docker-compose logs -f"
echo -e "${YELLOW}🛑 Stop:${NC} ./cleanup.sh"
echo ""
echo -e "${GREEN}Enjoy the demo! 🎉${NC}"