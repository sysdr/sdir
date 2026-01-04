#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${RED}🧹 Cleaning up Hot Key Demo...${NC}"
echo ""



echo -e "${BLUE}Stopping Docker containers...${NC}"
docker-compose down -v 2>/dev/null

echo -e "${BLUE}Removing Docker images...${NC}"
docker rmi hotkey-demo_backend hotkey-demo_frontend 2>/dev/null


echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}✅ Cleanup complete!${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "${YELLOW}All containers, images, and files have been removed.${NC}"
echo ""