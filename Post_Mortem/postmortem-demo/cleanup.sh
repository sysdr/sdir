#!/bin/bash

# Post-Mortem Demo Cleanup Script
set -e

BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════╗"
echo "║       Cleaning Up Demo Resources      ║"
echo "╚═══════════════════════════════════════╝"
echo -e "${NC}"

print_status "Stopping services..."
docker-compose down -v --remove-orphans

print_status "Removing images..."
docker-compose down --rmi local --remove-orphans

print_status "Cleaning up volumes..."
docker volume prune -f

print_status "Cleaning up build cache..."
docker builder prune -f

print_success "Demo cleanup completed!"
echo ""
echo "All services stopped and resources cleaned up."
echo "You can run './demo.sh' again to restart the demo."
