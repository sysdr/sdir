#!/bin/bash

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${YELLOW}=========================================="
echo "Connection Exhaustion Demo Cleanup"
echo "==========================================${NC}"
echo ""

echo -e "${BLUE}Stopping all containers...${NC}"
docker-compose down

echo -e "${BLUE}Removing Docker images...${NC}"
docker-compose down --rmi all 2>/dev/null || true

echo -e "${BLUE}Removing volumes...${NC}"
docker-compose down --volumes 2>/dev/null || true



echo ""
echo -e "${GREEN}=========================================="
echo "Cleanup complete!"
echo "==========================================${NC}"
echo ""
echo -e "${GREEN}All containers, images, and files have been removed.${NC}"
echo -e "${BLUE}To run the demo again, execute: ${YELLOW}./demo.sh${NC}"