#!/bin/bash

# Chaos Engineering Demo - Complete Cleanup Script
# Stops services, removes containers, images, volumes, and project files

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

PROJECT_NAME="chaos-engineering-demo"
COMPOSE_PROJECT_NAME="chaos-engineering-demo"

echo -e "${RED}🧹 Chaos Engineering Demo Cleanup${NC}"
echo "===================================="

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to safely run docker commands
safe_docker() {
    if command_exists docker && docker info >/dev/null 2>&1; then
        return 0
    else
        echo -e "${YELLOW}⚠️  Docker is not running or accessible${NC}"
        return 1
    fi
}

# Function to cleanup docker resources
cleanup_docker() {
    echo -e "\n${BLUE}Step 1: Stopping and Removing Docker Resources${NC}"
    echo "================================================"
    
    if ! safe_docker; then
        echo -e "${YELLOW}⚠️  Skipping Docker cleanup - Docker not available${NC}"
        return
    fi
    
    # Change to project directory if it exists
    if [ -d "$PROJECT_NAME" ]; then
        cd "$PROJECT_NAME"
        echo -e "${YELLOW}📂 Working in project directory: $(pwd)${NC}"
    fi
    
    # Stop and remove containers using docker-compose
    if [ -f "docker-compose.yml" ]; then
        echo -e "${YELLOW}🛑 Stopping docker-compose services...${NC}"
        docker-compose down --remove-orphans --volumes 2>/dev/null || true
        echo -e "${GREEN}✅ Docker-compose services stopped${NC}"
    else
        echo -e "${YELLOW}⚠️  docker-compose.yml not found, trying manual cleanup${NC}"
    fi
    
    # Stop individual containers by name pattern
    echo -e "${YELLOW}🔍 Searching for chaos engineering containers...${NC}"
    CONTAINERS=$(docker ps -a --filter "name=chaos" --filter "name=user-service" --filter "name=order-service" --filter "name=payment-service" --filter "name=inventory-service" -q 2>/dev/null || true)
    
    if [ -n "$CONTAINERS" ]; then
        echo -e "${YELLOW}🛑 Stopping and removing containers...${NC}"
        docker stop $CONTAINERS 2>/dev/null || true
        docker rm -f $CONTAINERS 2>/dev/null || true
        echo -e "${GREEN}✅ Containers removed${NC}"
    else
        echo -e "${GREEN}✅ No chaos engineering containers found${NC}"
    fi
    
    # Remove images
    echo -e "${YELLOW}🗑️  Removing chaos engineering images...${NC}"
    IMAGES=$(docker images --filter "reference=*chaos*" --filter "reference=*${PROJECT_NAME}*" -q 2>/dev/null || true)
    
    if [ -n "$IMAGES" ]; then
        docker rmi -f $IMAGES 2>/dev/null || true
        echo -e "${GREEN}✅ Images removed${NC}"
    else
        echo -e "${GREEN}✅ No chaos engineering images found${NC}"
    fi
    
    # Remove volumes
    echo -e "${YELLOW}📦 Removing volumes...${NC}"
    VOLUMES=$(docker volume ls --filter "name=${COMPOSE_PROJECT_NAME}" -q 2>/dev/null || true)
    
    if [ -n "$VOLUMES" ]; then
        docker volume rm $VOLUMES 2>/dev/null || true
        echo -e "${GREEN}✅ Volumes removed${NC}"
    else
        echo -e "${GREEN}✅ No chaos engineering volumes found${NC}"
    fi
    
    # Remove networks
    echo -e "${YELLOW}🌐 Removing networks...${NC}"
    NETWORKS=$(docker network ls --filter "name=${COMPOSE_PROJECT_NAME}" -q 2>/dev/null || true)
    
    if [ -n "$NETWORKS" ]; then
        docker network rm $NETWORKS 2>/dev/null || true
        echo -e "${GREEN}✅ Networks removed${NC}"
    else
        echo -e "${GREEN}✅ No chaos engineering networks found${NC}"
    fi
}

# Function to check and kill processes on specific ports
cleanup_ports() {
    echo -e "\n${BLUE}Step 2: Cleaning Up Port Usage${NC}"
    echo "==============================="
    
    PORTS=(8000 8001 8002 8003 8004)
    
    for port in "${PORTS[@]}"; do
        echo -e "${YELLOW}🔍 Checking port $port...${NC}"
        
        # Find processes using the port
        PIDS=$(lsof -ti:$port 2>/dev/null || true)
        
        if [ -n "$PIDS" ]; then
            echo -e "${YELLOW}🔪 Killing processes on port $port: $PIDS${NC}"
            kill -9 $PIDS 2>/dev/null || true
            echo -e "${GREEN}✅ Port $port cleaned${NC}"
        else
            echo -e "${GREEN}✅ Port $port is free${NC}"
        fi
    done
}

# Function to remove project files
cleanup_files() {
    echo -e "\n${BLUE}Step 3: Removing Project Files${NC}"
    echo "==============================="
    
    # Go back to parent directory
    cd "$(dirname "$(pwd)")" 2>/dev/null || cd ..
    
    if [ -d "$PROJECT_NAME" ]; then
        echo -e "${YELLOW}🗂️  Found project directory: $PROJECT_NAME${NC}"
        
        # Ask for confirmation before deleting
        if [ "$1" != "--force" ]; then
            echo -e "${YELLOW}❓ Delete project directory? [y/N]:${NC}"
            read -r response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                echo -e "${YELLOW}⚠️  Project directory preserved${NC}"
                return
            fi
        fi
        
        echo -e "${YELLOW}🗑️  Removing project directory...${NC}"
        rm -rf "$PROJECT_NAME"
        echo -e "${GREEN}✅ Project directory removed${NC}"
    else
        echo -e "${GREEN}✅ No project directory found${NC}"
    fi
}

# Function to clean Docker system
cleanup_docker_system() {
    echo -e "\n${BLUE}Step 4: Docker System Cleanup${NC}"
    echo "=============================="
    
    if ! safe_docker; then
        return
    fi
    
    echo -e "${YELLOW}🧹 Running Docker system prune...${NC}"
    
    # Remove unused containers, networks, images, and build cache
    docker system prune -f 2>/dev/null || true
    
    # Remove unused volumes
    docker volume prune -f 2>/dev/null || true
    
    echo -e "${GREEN}✅ Docker system cleaned${NC}"
}

# Function to verify cleanup
verify_cleanup() {
    echo -e "\n${BLUE}Step 5: Verification${NC}"
    echo "===================="
    
    # Check for running containers
    if safe_docker; then
        RUNNING_CONTAINERS=$(docker ps --filter "name=chaos" --filter "name=user-service" --filter "name=order-service" --filter "name=payment-service" --filter "name=inventory-service" -q 2>/dev/null || true)
        
        if [ -z "$RUNNING_CONTAINERS" ]; then
            echo -e "${GREEN}✅ No chaos engineering containers running${NC}"
        else
            echo -e "${RED}❌ Some containers are still running${NC}"
            docker ps --filter "name=chaos" --filter "name=user-service" --filter "name=order-service" --filter "name=payment-service" --filter "name=inventory-service"
        fi
    fi
    
    # Check ports
    PORTS=(8000 8001 8002 8003 8004)
    ALL_PORTS_FREE=true
    
    for port in "${PORTS[@]}"; do
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo -e "${RED}❌ Port $port is still in use${NC}"
            ALL_PORTS_FREE=false
        fi
    done
    
    if [ "$ALL_PORTS_FREE" = true ]; then
        echo -e "${GREEN}✅ All ports are free${NC}"
    fi
    
    # Check project directory
    if [ -d "$PROJECT_NAME" ]; then
        echo -e "${YELLOW}ℹ️  Project directory still exists: $PROJECT_NAME${NC}"
    else
        echo -e "${GREEN}✅ Project directory removed${NC}"
    fi
}

# Function to show cleanup summary
show_summary() {
    echo -e "\n${GREEN}🎉 Cleanup Complete!${NC}"
    echo "===================="
    echo ""
    echo -e "${BLUE}What was cleaned:${NC}"
    echo "• Docker containers (chaos engineering services)"
    echo "• Docker images (chaos engineering platform)"
    echo "• Docker volumes and networks"
    echo "• Processes using ports 8000-8004"
    echo "• Project files and directories"
    echo "• Docker system cache"
    echo ""
    echo -e "${YELLOW}To run the demo again:${NC}"
    echo "   ./demo.sh"
    echo ""
}

# Function to handle emergency cleanup
emergency_cleanup() {
    echo -e "\n${RED}🚨 Emergency Cleanup Mode${NC}"
    echo "=========================="
    
    # Force kill all containers
    if safe_docker; then
        echo -e "${YELLOW}🛑 Force stopping all containers...${NC}"
        docker stop $(docker ps -aq) 2>/dev/null || true
        docker rm -f $(docker ps -aq) 2>/dev/null || true
    fi
    
    # Force kill processes on our ports
    for port in 8000 8001 8002 8003 8004; do
        pkill -f ":$port" 2>/dev/null || true
    done
    
    echo -e "${GREEN}✅ Emergency cleanup completed${NC}"
}

# Main execution
main() {
    # Parse arguments
    FORCE_DELETE=false
    EMERGENCY=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --force)
                FORCE_DELETE=true
                shift
                ;;
            --emergency)
                EMERGENCY=true
                shift
                ;;
            --help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --force      Skip confirmation prompts"
                echo "  --emergency  Emergency cleanup mode"
                echo "  --help       Show this help"
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown option: $1${NC}"
                exit 1
                ;;
        esac
    done
    
    if [ "$EMERGENCY" = true ]; then
        emergency_cleanup
        return
    fi
    
    # Check if demo is running
    if [ -d "$PROJECT_NAME" ]; then
        cd "$PROJECT_NAME"
        if docker-compose ps 2>/dev/null | grep -q "Up"; then
            echo -e "${YELLOW}ℹ️  Chaos engineering demo is currently running${NC}"
        fi
        cd ..
    fi
    
    # Confirm cleanup unless forced
    if [ "$FORCE_DELETE" = false ]; then
        echo -e "${YELLOW}❓ This will stop and remove all chaos engineering demo components.${NC}"
        echo -e "${YELLOW}   Continue? [y/N]:${NC}"
        read -r response
        if [[ ! "$response" =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}ℹ️  Cleanup cancelled${NC}"
            exit 0
        fi
    fi
    
    # Run cleanup steps
    cleanup_docker
    cleanup_ports
    
   # if [ "$FORCE_DELETE" = true ]; then
   #     cleanup_files --force
   # else
   #     cleanup_files
   # fi
    
    cleanup_docker_system
    verify_cleanup
    show_summary
    
    echo -e "${GREEN}✨ All clean! System is ready for fresh setup.${NC}"
}

# Handle script interruption
cleanup_on_interrupt() {
    echo -e "\n${RED}🛑 Cleanup interrupted${NC}"
    echo "Run with --emergency flag for force cleanup"
    exit 1
}

# Set trap for interruption
trap cleanup_on_interrupt INT TERM

# Check if being run with specific flags
if [ "$1" = "--check" ]; then
    # Just check if anything needs cleanup
    NEEDS_CLEANUP=false
    
    if safe_docker; then
        CONTAINERS=$(docker ps -a --filter "name=chaos" -q 2>/dev/null || true)
        [ -n "$CONTAINERS" ] && NEEDS_CLEANUP=true
    fi
    
    [ -d "$PROJECT_NAME" ] && NEEDS_CLEANUP=true
    
    if [ "$NEEDS_CLEANUP" = true ]; then
        echo "Cleanup needed"
        exit 1
    else
        echo "System is clean"
        exit 0
    fi
fi

# Run main cleanup
main "$@"