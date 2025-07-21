#!/bin/bash

# Search Scaling Demo - Build Script
# This script builds and prepares the entire demo environment

set -e  # Exit on any error

echo "🚀 Building Search Scaling Demo Environment"
echo "=========================================="

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
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

# Check if Docker is running
check_docker() {
    print_status "Checking Docker installation..."
    if ! docker info > /dev/null 2>&1; then
        print_error "Docker is not running or not installed. Please start Docker and try again."
        exit 1
    fi
    print_success "Docker is running"
}

# Check if Docker Compose is available
check_docker_compose() {
    print_status "Checking Docker Compose..."
    if ! docker-compose --version > /dev/null 2>&1; then
        print_error "Docker Compose is not available. Please install Docker Compose and try again."
        exit 1
    fi
    print_success "Docker Compose is available"
}

# Create necessary directories
create_directories() {
    print_status "Creating necessary directories..."
    
    mkdir -p logs
    mkdir -p data
    mkdir -p app/static
    
    print_success "Directories created"
}

# Build Docker images
build_images() {
    print_status "Building Docker images..."
    
    # Build the main application image
    docker-compose build --no-cache
    
    print_success "Docker images built successfully"
}

# Initialize the database schema
init_database() {
    print_status "Initializing database schema..."
    
    # Check if init.sql exists
    if [ ! -f "config/init.sql" ]; then
        print_error "Database initialization file config/init.sql not found"
        exit 1
    fi
    
    print_success "Database schema ready for initialization"
}

# Create a simple static file for the app
create_static_files() {
    print_status "Creating static files..."
    
    # Create a simple CSS file if it doesn't exist
    if [ ! -f "app/static/style.css" ]; then
        cat > app/static/style.css << 'EOF'
/* Additional styles for the search demo */
.additional-styles {
    margin-top: 20px;
    padding: 15px;
    background: #f0f8ff;
    border-radius: 8px;
    border-left: 4px solid #1e90ff;
}

.status-indicator {
    display: inline-block;
    width: 12px;
    height: 12px;
    border-radius: 50%;
    margin-right: 8px;
}

.status-healthy {
    background-color: #34a853;
}

.status-degraded {
    background-color: #fbbc04;
}

.status-unhealthy {
    background-color: #ea4335;
}
EOF
        print_success "Static files created"
    else
        print_status "Static files already exist"
    fi
}

# Verify all required files exist
verify_files() {
    print_status "Verifying required files..."
    
    required_files=(
        "app/app.py"
        "app/templates/index.html"
        "docker-compose.yml"
        "Dockerfile"
        "requirements.txt"
        "config/init.sql"
    )
    
    for file in "${required_files[@]}"; do
        if [ ! -f "$file" ]; then
            print_error "Required file not found: $file"
            exit 1
        fi
    done
    
    print_success "All required files verified"
}

# Main build process
main() {
    echo ""
    print_status "Starting build process..."
    
    check_docker
    check_docker_compose
    verify_files
    create_directories
    create_static_files
    init_database
    build_images
    
    echo ""
    print_success "Build completed successfully! 🎉"
    echo ""
    echo "Next steps:"
    echo "1. Run './start-demo.sh' to start the demo"
    echo "2. Open http://localhost:5000 in your browser"
    echo "3. Run './simulate-load.sh' to simulate search load"
    echo "4. Run './cleanup.sh' to stop and clean up"
    echo ""
}

# Run main function
main "$@" 