#!/bin/bash

# Cleanup script for Traffic Shaping and Rate Limiting Demo

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}[CLEANUP]${NC} $1"
}

print_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

print_step "Stopping all containers..."
docker-compose down

print_step "Removing volumes..."
docker-compose down -v

print_step "Removing unused Docker resources..."
docker system prune -f

print_step "Removing log files..."
rm -rf logs/*

print_info "Cleanup completed!"
print_info "All containers, volumes, and temporary files have been removed."
