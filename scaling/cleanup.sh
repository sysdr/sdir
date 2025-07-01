#!/bin/bash

# cleanup.sh - Clean up Scaling Demo Environment
# This script stops all services and removes the demo environment

set -e

echo "🧹 Cleaning up Scaling to 1M Users Demo Environment..."

# Function to check if directory exists
check_demo_dir() {
    if [ ! -d "scaling-demo" ]; then
        echo "❌ Demo directory 'scaling-demo' not found"
        echo "💡 Make sure you're in the correct directory where demo.sh was run"
        exit 1
    fi
}

# Function to stop Docker services
stop_docker_services() {
    echo "🐳 Stopping Docker services..."
    cd scaling-demo
    
    if [ -f "docker-compose.yml" ]; then
        # Stop and remove containers
        docker-compose down --volumes --remove-orphans 2>/dev/null || true
        
        # Remove images
        echo "🗑️ Removing Docker images..."
        docker images --format "table {{.Repository}}\t{{.Tag}}\t{{.ID}}" | grep "scaling-demo" | awk '{print $3}' | xargs docker rmi -f 2>/dev/null || true
        
        # Clean up unused volumes and networks
        docker volume prune -f 2>/dev/null || true
        docker network prune -f 2>/dev/null || true
        
        echo "✅ Docker services stopped and cleaned"
    else
        echo "⚠️ docker-compose.yml not found, skipping Docker cleanup"
    fi
    
    cd ..
}

# Function to stop local Python processes
stop_local_processes() {
    echo "🐍 Stopping local Python processes..."
    
    # Find and kill processes running on port 5000
    PIDS=$(lsof -t -i:5000 2>/dev/null || true)
    if [ ! -z "$PIDS" ]; then
        echo "🔄 Stopping processes on port 5000..."
        echo $PIDS | xargs kill -TERM 2>/dev/null || true
        sleep 2
        # Force kill if still running
        echo $PIDS | xargs kill -KILL 2>/dev/null || true
        echo "✅ Processes stopped"
    else
        echo "ℹ️ No processes found on port 5000"
    fi
    
    # Clean up any Flask processes
    pkill -f "python.*app.py" 2>/dev/null || true
    pkill -f "flask" 2>/dev/null || true
}

# Function to remove demo directory
remove_demo_directory() {
    echo "📁 Removing demo directory..."
    
    # Ask for confirmation
    read -p "❓ Do you want to permanently delete the 'scaling-demo' directory? (y/N): " -n 1 -r
    echo
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -rf scaling-demo
        echo "✅ Demo directory removed"
    else
        echo "⏭️ Demo directory preserved"
        echo "💡 You can manually delete it later with: rm -rf scaling-demo"
    fi
}

# Function to clean up Python virtual environment
cleanup_python_env() {
    echo "🐍 Cleaning up Python environment..."
    
    if [ -d "scaling-demo/venv" ]; then
        # Deactivate virtual environment if active
        if [[ "$VIRTUAL_ENV" == *"scaling-demo/venv"* ]]; then
            deactivate 2>/dev/null || true
        fi
        
        # Remove virtual environment
        rm -rf scaling-demo/venv
        echo "✅ Python virtual environment removed"
    else
        echo "ℹ️ No Python virtual environment found"
    fi
}

# Function to show cleanup summary
show_cleanup_summary() {
    echo ""
    echo "🎉 Cleanup completed successfully!"
    echo ""
    echo "📋 What was cleaned up:"
    echo "   ✅ Docker containers and images"
    echo "   ✅ Docker volumes and networks"
    echo "   ✅ Local Python processes"
    echo "   ✅ Python virtual environment"
    echo "   ✅ Port 5000 processes"
    echo ""
    echo "🔍 To verify cleanup:"
    echo "   docker ps -a  # Should show no scaling-demo containers"
    echo "   docker images | grep scaling-demo  # Should return empty"
    echo "   lsof -i:5000  # Should show no processes"
    echo ""
    echo "💡 Tips:"
    echo "   • You can run demo.sh again to recreate the environment"
    echo "   • Check 'docker system df' to see overall Docker disk usage"
    echo "   • Run 'docker system prune' to clean up all unused Docker resources"
}

# Function to handle cleanup errors
handle_cleanup_error() {
    echo ""
    echo "❌ An error occurred during cleanup"
    echo "🔧 Manual cleanup commands:"
    echo ""
    echo "Stop Docker services:"
    echo "   cd scaling-demo && docker-compose down --volumes --remove-orphans"
    echo ""
    echo "Remove Docker images:"
    echo "   docker images | grep scaling-demo | awk '{print \$3}' | xargs docker rmi -f"
    echo ""
    echo "Kill processes on port 5000:"
    echo "   sudo lsof -t -i:5000 | xargs kill -9"
    echo ""
    echo "Remove demo directory:"
    echo "   rm -rf scaling-demo"
    echo ""
}

# Main cleanup execution
main() {
    echo "🚀 Starting cleanup process..."
    echo ""
    
    # Set error handler
    trap 'handle_cleanup_error' ERR
    
    # Check if demo directory exists
    check_demo_dir
    
    # Stop Docker services
    stop_docker_services
    
    # Stop local processes
    stop_local_processes
    
    # Clean up Python environment
    cleanup_python_env
    
    # Remove demo directory (with confirmation)
    remove_demo_directory
    
    # Show cleanup summary
    show_cleanup_summary
}

# Run main function
main "$@"