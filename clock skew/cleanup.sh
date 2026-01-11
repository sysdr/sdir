#!/bin/bash
# ==============================================
# Cleanup Script for Clock Skew Demo
# ==============================================
# Stops and removes all containers, networks, and images
# ==============================================

# Colors for terminal output
GREEN='\033[0;32m'
BLUE='\033[1;34m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}>>> Cleaning up Clock Skew Demo...${NC}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEMO_DIR="$SCRIPT_DIR/skew-demo"

# Check if demo directory exists
if [ ! -d "$DEMO_DIR" ] || [ ! -f "$DEMO_DIR/docker-compose.yml" ]; then
    echo -e "${YELLOW}No demo environment found. Cleaning up any orphaned containers...${NC}"
else
    # Navigate to demo directory and stop containers
    cd "$DEMO_DIR"
    echo -e "${CYAN}Stopping containers from docker-compose...${NC}"
    docker-compose down -v 2>/dev/null || true
fi

# Check if there are any orphaned containers
ORPHANED=$(docker ps -a --filter "name=skew-demo" --format "{{.Names}}" 2>/dev/null || true)
if [ -n "$ORPHANED" ]; then
    echo -e "${CYAN}Removing orphaned containers...${NC}"
    echo "$ORPHANED" | xargs docker rm -f 2>/dev/null || true
fi

# Check if there are any orphaned networks
ORPHANED_NETWORKS=$(docker network ls --filter "name=skew-demo" --format "{{.Name}}" 2>/dev/null || true)
if [ -n "$ORPHANED_NETWORKS" ]; then
    echo -e "${CYAN}Removing orphaned networks...${NC}"
    echo "$ORPHANED_NETWORKS" | xargs docker network rm 2>/dev/null || true
fi

# Remove images (non-interactive)
echo -e "${CYAN}Removing demo images...${NC}"
docker images --filter "reference=skew-demo*" --format "{{.ID}}" | xargs docker rmi -f 2>/dev/null || true

echo -e "\n${GREEN}>>> Cleanup Complete! <<<${NC}\n"

# Verify cleanup
REMAINING=$(docker ps -a --filter "name=skew-demo" --format "{{.Names}}" 2>/dev/null || true)
if [ -z "$REMAINING" ]; then
    echo -e "${GREEN}All demo containers have been removed.${NC}"
else
    echo -e "${YELLOW}Warning: Some containers may still exist:${NC}"
    echo "$REMAINING"
fi
