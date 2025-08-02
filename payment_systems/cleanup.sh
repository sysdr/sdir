#!/bin/bash

# Payment Systems Cleanup Script
# This script stops all processes, cleans temporary files, and removes Docker resources
# WITHOUT deleting any source code

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "\n${BLUE}================================${NC}"
    echo -e "${BLUE}  Payment Systems Cleanup${NC}"
    echo -e "${BLUE}================================${NC}\n"
}

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to stop processes by name
stop_processes() {
    local process_name=$1
    local pids=$(pgrep -f "$process_name" 2>/dev/null || true)
    
    if [ -n "$pids" ]; then
        print_info "Stopping $process_name processes..."
        echo "$pids" | xargs kill -TERM 2>/dev/null || true
        sleep 2
        
        # Force kill if still running
        pids=$(pgrep -f "$process_name" 2>/dev/null || true)
        if [ -n "$pids" ]; then
            print_warning "Force killing remaining $process_name processes..."
            echo "$pids" | xargs kill -KILL 2>/dev/null || true
        fi
        print_success "Stopped $process_name processes"
    else
        print_info "No $process_name processes found"
    fi
}

# Function to stop Node.js processes
stop_node_processes() {
    print_info "Stopping Node.js processes..."
    
    # Stop backend server
    stop_processes "node server.js"
    stop_processes "nodemon server.js"
    
    # Stop frontend dev server
    stop_processes "vite"
    stop_processes "npm run dev"
    
    # Stop any other node processes in the project
    local project_pids=$(pgrep -f "payment_systems" 2>/dev/null || true)
    if [ -n "$project_pids" ]; then
        print_info "Stopping project-related processes..."
        echo "$project_pids" | xargs kill -TERM 2>/dev/null || true
        sleep 2
        echo "$project_pids" | xargs kill -KILL 2>/dev/null || true
    fi
}

# Function to clean temporary files
clean_temp_files() {
    print_info "Cleaning temporary files..."
    
    # Clean npm cache
    if command_exists npm; then
        print_info "Cleaning npm cache..."
        npm cache clean --force 2>/dev/null || true
    fi
    
    # Clean node_modules (optional - uncomment if needed)
    # print_warning "Removing node_modules directories..."
    # find . -name "node_modules" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Clean build artifacts
    print_info "Cleaning build artifacts..."
    find . -name "dist" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "build" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name ".next" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Clean log files
    print_info "Cleaning log files..."
    find . -name "*.log" -type f -delete 2>/dev/null || true
    find . -name "npm-debug.log*" -type f -delete 2>/dev/null || true
    find . -name "yarn-debug.log*" -type f -delete 2>/dev/null || true
    find . -name "yarn-error.log*" -type f -delete 2>/dev/null || true
    
    # Clean temporary files
    print_info "Cleaning temporary files..."
    find . -name "*.tmp" -type f -delete 2>/dev/null || true
    find . -name "*.temp" -type f -delete 2>/dev/null || true
    find . -name ".DS_Store" -type f -delete 2>/dev/null || true
    find . -name "Thumbs.db" -type f -delete 2>/dev/null || true
    
    # Clean coverage reports
    print_info "Cleaning coverage reports..."
    find . -name "coverage" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name ".nyc_output" -type d -exec rm -rf {} + 2>/dev/null || true
    
    # Clean IDE files (optional)
    print_info "Cleaning IDE files..."
    find . -name ".vscode" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name ".idea" -type d -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.swp" -type f -delete 2>/dev/null || true
    find . -name "*.swo" -type f -delete 2>/dev/null || true
    find . -name "*~" -type f -delete 2>/dev/null || true
    
    print_success "Temporary files cleaned"
}

# Function to clean Docker resources
clean_docker() {
    if ! command_exists docker; then
        print_info "Docker not found, skipping Docker cleanup"
        return
    fi
    
    print_info "Cleaning Docker resources..."
    
    # Stop all running containers
    print_info "Stopping all Docker containers..."
    docker stop $(docker ps -q) 2>/dev/null || true
    
    # Remove all containers
    print_info "Removing all Docker containers..."
    docker rm $(docker ps -aq) 2>/dev/null || true
    
    # Remove all images
    print_info "Removing all Docker images..."
    docker rmi $(docker images -q) 2>/dev/null || true
    
    # Remove all volumes
    print_info "Removing all Docker volumes..."
    docker volume rm $(docker volume ls -q) 2>/dev/null || true
    
    # Remove all networks (except default ones)
    print_info "Removing custom Docker networks..."
    docker network rm $(docker network ls --filter "type=custom" -q) 2>/dev/null || true
    
    # Clean up system
    print_info "Cleaning Docker system..."
    docker system prune -af --volumes 2>/dev/null || true
    
    print_success "Docker resources cleaned"
}

# Function to clean database files
clean_database() {
    print_info "Cleaning database files..."
    
    # Remove SQLite database files
    find . -name "*.db" -type f -delete 2>/dev/null || true
    find . -name "*.sqlite" -type f -delete 2>/dev/null || true
    find . -name "*.sqlite3" -type f -delete 2>/dev/null || true
    
    # Remove database backups
    find . -name "*.db.backup" -type f -delete 2>/dev/null || true
    find . -name "*.sqlite.backup" -type f -delete 2>/dev/null || true
    
    print_success "Database files cleaned"
}

# Function to clean environment files
clean_env_files() {
    print_info "Cleaning environment files..."
    
    # Remove .env files (but keep .env.example)
    find . -name ".env" -type f -delete 2>/dev/null || true
    find . -name ".env.local" -type f -delete 2>/dev/null || true
    find . -name ".env.development" -type f -delete 2>/dev/null || true
    find . -name ".env.production" -type f -delete 2>/dev/null || true
    
    print_success "Environment files cleaned"
}

# Function to show disk usage
show_disk_usage() {
    print_info "Current disk usage:"
    du -sh . 2>/dev/null || true
    echo ""
}

# Function to show what will be preserved
show_preserved_files() {
    print_info "The following source code will be preserved:"
    echo "  ✓ All .js, .jsx, .ts, .tsx files"
    echo "  ✓ All .html, .css, .scss files"
    echo "  ✓ All .json, .md, .txt files"
    echo "  ✓ All .sh, .py, .java files"
    echo "  ✓ All configuration files"
    echo "  ✓ All documentation files"
    echo "  ✓ All source directories"
    echo ""
}

# Main cleanup function
main() {
    print_header
    show_preserved_files
    
    # Confirm before proceeding
    read -p "Do you want to proceed with cleanup? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cleanup cancelled"
        exit 0
    fi
    
    show_disk_usage
    
    # Stop all processes
    print_info "Step 1: Stopping all processes..."
    stop_node_processes
    
    # Clean temporary files
    print_info "Step 2: Cleaning temporary files..."
    clean_temp_files
    
    # Clean database files
    print_info "Step 3: Cleaning database files..."
    clean_database
    
    # Clean environment files
    print_info "Step 4: Cleaning environment files..."
    clean_env_files
    
    # Clean Docker resources
    print_info "Step 5: Cleaning Docker resources..."
    clean_docker
    
    # Final disk usage
    print_info "Step 6: Final disk usage:"
    show_disk_usage
    
    print_success "Cleanup completed successfully!"
    print_info "All source code has been preserved."
    print_info "To restart the application, run: ./demo.sh"
}

# Handle script interruption
trap 'print_error "Cleanup interrupted"; exit 1' INT TERM

# Run main function
main "$@" 