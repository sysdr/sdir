#!/bin/bash

echo "🧹 Cleaning up Scalability Testing Demo..."
echo "=========================================="

# Function to check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo "❌ Docker is not running or not accessible"
        return 1
    fi
    return 0
}

# Function to stop and remove containers
cleanup_containers() {
    echo "🐳 Stopping and removing Docker containers..."
    
    if [ -f "docker-compose.yml" ]; then
        echo "  Stopping docker-compose services..."
        docker-compose down -v --remove-orphans 2>/dev/null || true
        
        echo "  Removing any remaining containers..."
        docker ps -a --filter "name=scalability-testing-demo" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
    fi
    
    # Remove any containers that might be using our ports
    echo "  Checking for containers using our ports..."
    for port in 8000 9090 3000 6379; do
        container_id=$(docker ps -q --filter "publish=$port" 2>/dev/null || true)
        if [ ! -z "$container_id" ]; then
            echo "    Stopping container using port $port: $container_id"
            docker stop "$container_id" 2>/dev/null || true
            docker rm "$container_id" 2>/dev/null || true
        fi
    done
}

# Function to remove Docker images
cleanup_images() {
    echo "🗑️  Removing Docker images..."
    
    # Remove specific images
    echo "  Removing scalability-testing-demo images..."
    docker images --filter "reference=scalability-testing-demo*" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true
    
    # Remove dangling images
    echo "  Removing dangling images..."
    docker image prune -f 2>/dev/null || true
    
    # Remove unused images (optional - uncomment if you want to remove all unused images)
    # echo "  Removing unused images..."
    # docker image prune -a -f 2>/dev/null || true
}

# Function to clean up volumes
cleanup_volumes() {
    echo "💾 Cleaning up Docker volumes..."
    
    # Remove volumes created by docker-compose
    if [ -f "docker-compose.yml" ]; then
        echo "  Removing docker-compose volumes..."
        docker-compose down -v 2>/dev/null || true
    fi
    
    # Remove any volumes with our project name
    echo "  Removing project-specific volumes..."
    docker volume ls --filter "name=scalability-testing-demo" --format "{{.Name}}" | xargs -r docker volume rm 2>/dev/null || true
    
    # Remove dangling volumes
    echo "  Removing dangling volumes..."
    docker volume prune -f 2>/dev/null || true
}

# Function to clean up networks
cleanup_networks() {
    echo "🌐 Cleaning up Docker networks..."
    
    # Remove networks created by docker-compose
    if [ -f "docker-compose.yml" ]; then
        echo "  Removing docker-compose networks..."
        docker-compose down --remove-orphans 2>/dev/null || true
    fi
    
    # Remove any networks with our project name
    echo "  Removing project-specific networks..."
    docker network ls --filter "name=scalability-testing-demo" --format "{{.ID}}" | xargs -r docker network rm 2>/dev/null || true
    
    # Remove dangling networks
    echo "  Removing dangling networks..."
    docker network prune -f 2>/dev/null || true
}

# Function to clean up temporary files
cleanup_temp_files() {
    echo "📁 Cleaning up temporary files..."
    
    # Remove Python cache files
    echo "  Removing Python cache files..."
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "*.pyo" -delete 2>/dev/null || true
    find . -name "*.pyd" -delete 2>/dev/null || true
    find . -name ".Python" -delete 2>/dev/null || true
    
    # Remove Python build artifacts
    echo "  Removing Python build artifacts..."
    find . -type d -name "build" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "dist" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "*.egg-info" -exec rm -rf {} + 2>/dev/null || true
    
    # Remove virtual environment directories
    echo "  Removing virtual environment directories..."
    find . -type d -name "venv" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name "env" -exec rm -rf {} + 2>/dev/null || true
    find . -type d -name ".venv" -exec rm -rf {} + 2>/dev/null || true
    
    # Remove log files
    echo "  Removing log files..."
    find . -name "*.log" -delete 2>/dev/null || true
    rm -rf logs/ 2>/dev/null || true
    
    # Remove results directory
    echo "  Removing results directory..."
    rm -rf results/ 2>/dev/null || true
    
    # Remove temporary files
    echo "  Removing temporary files..."
    find . -name "*.tmp" -delete 2>/dev/null || true
    find . -name "*.temp" -delete 2>/dev/null || true
    find . -name ".DS_Store" -delete 2>/dev/null || true
    find . -name "Thumbs.db" -delete 2>/dev/null || true
}

# Function to clean up system processes
cleanup_processes() {
    echo "⚙️  Checking for related processes..."
    
    # Check for processes using our ports
    for port in 8000 9090 3000 6379; do
        pid=$(lsof -ti:$port 2>/dev/null || true)
        if [ ! -z "$pid" ]; then
            echo "  Found process using port $port (PID: $pid)"
            read -p "    Do you want to kill this process? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "    Killing process $pid..."
                kill -9 "$pid" 2>/dev/null || true
            fi
        fi
    done
}

# Function to reset project state
reset_project() {
    echo "🔄 Resetting project state..."
    
    # Remove any lock files
    echo "  Removing lock files..."
    rm -f .env 2>/dev/null || true
    rm -f docker-compose.override.yml 2>/dev/null || true
    
    # Reset any modified files to original state (if using git)
    if [ -d ".git" ]; then
        echo "  Resetting git changes..."
        git checkout -- . 2>/dev/null || true
        git clean -fd 2>/dev/null || true
    fi
}

# Main cleanup execution
main() {
    echo "Starting comprehensive cleanup..."
    echo ""
    
    # Check if Docker is available
    if check_docker; then
        cleanup_containers
        cleanup_images
        cleanup_volumes
        cleanup_networks
    else
        echo "⚠️  Skipping Docker cleanup (Docker not available)"
    fi
    
    cleanup_temp_files
    cleanup_processes
    reset_project
    
    echo ""
    echo "✅ Cleanup completed successfully!"
    echo ""
    echo "🎯 What was cleaned up:"
    echo "  • Docker containers, images, volumes, and networks"
    echo "  • Python cache and build artifacts"
    echo "  • Virtual environment directories"
    echo "  • Log files and results"
    echo "  • Temporary files"
    echo "  • Project state reset"
    echo ""
    echo "🚀 To start fresh, run: ./demo.sh"
}

# Handle script interruption
trap 'echo ""; echo "❌ Cleanup interrupted"; exit 1' INT TERM

# Run main cleanup
main 