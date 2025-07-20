#!/bin/bash

# Cleanup script for Serverless Scaling Demo
# System Design Interview Roadmap - Issue #101

set -e

echo "🧹 Starting Serverless Scaling Demo Cleanup..."

# Function to check if we're in the demo directory
check_demo_directory() {
    if [[ ! -f "docker-compose.yml" ]] || [[ ! -d "src" ]]; then
        echo "❌ This doesn't appear to be the serverless scaling demo directory."
        echo "Please run this script from the serverless-scaling-demo directory."
        exit 1
    fi
}

# Stop and remove Docker containers
cleanup_docker() {
    echo "🐳 Stopping Docker containers..."
    
    # Stop all services including profiles
    docker-compose --profile load-test down --volumes --remove-orphans 2>/dev/null || true
    docker-compose down --volumes --remove-orphans 2>/dev/null || true
    
    # Remove any dangling containers related to this project
    echo "🗑️ Removing project containers..."
    docker ps -a --filter "name=serverless-scaling" --format "{{.ID}}" | xargs -r docker rm -f 2>/dev/null || true
    
    # Clean up unused networks
    echo "🌐 Cleaning up networks..."
    docker network ls --filter "name=serverless-scaling" --format "{{.ID}}" | xargs -r docker network rm 2>/dev/null || true
    
    # Remove project images
    echo "🖼️ Removing project images..."
    docker images --filter "reference=serverless-scaling*" --format "{{.ID}}" | xargs -r docker rmi -f 2>/dev/null || true
    
    echo "✅ Docker cleanup completed"
}

# Clean up log files
cleanup_logs() {
    echo "📋 Cleaning up log files..."
    
    if [[ -d "logs" ]]; then
        rm -rf logs/*
        echo "✅ Log files cleaned"
    fi
}

# Clean up temporary files
cleanup_temp_files() {
    echo "🗂️ Cleaning up temporary files..."
    
    # Remove Python cache
    find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
    find . -name "*.pyc" -delete 2>/dev/null || true
    find . -name "*.pyo" -delete 2>/dev/null || true
    
    # Remove pytest cache
    rm -rf .pytest_cache 2>/dev/null || true
    
    # Remove any test artifacts
    rm -rf htmlcov/ 2>/dev/null || true
    rm -f .coverage 2>/dev/null || true
    
    echo "✅ Temporary files cleaned"
}

# Clean up Docker system (optional)
cleanup_docker_system() {
    read -p "🤔 Do you want to clean up unused Docker resources system-wide? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🧽 Running Docker system cleanup..."
        docker system prune -f --volumes
        echo "✅ Docker system cleanup completed"
    else
        echo "⏭️ Skipping Docker system cleanup"
    fi
}

# Reset demo to initial state (optional)
reset_demo() {
    read -p "🔄 Do you want to reset the demo to initial state (keeps source code)? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🔄 Resetting demo state..."
        
        # Recreate empty directories
        mkdir -p logs static templates config
        
        # Create empty log files
        touch logs/.gitkeep
        
        echo "✅ Demo reset to initial state"
    else
        echo "⏭️ Skipping demo reset"
    fi
}

# Remove entire demo directory (optional)
remove_demo_directory() {
    read -p "⚠️ Do you want to COMPLETELY REMOVE the demo directory? This cannot be undone! (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo "🗑️ Removing demo directory..."
        cd ..
        rm -rf serverless-scaling-demo
        echo "✅ Demo directory completely removed"
        echo "👋 Cleanup complete. Goodbye!"
        exit 0
    else
        echo "⏭️ Keeping demo directory"
    fi
}

# Verify cleanup
verify_cleanup() {
    echo "🔍 Verifying cleanup..."
    
    # Check for running containers
    running_containers=$(docker ps --filter "name=serverless-scaling" --format "{{.Names}}" 2>/dev/null || true)
    if [[ -n "$running_containers" ]]; then
        echo "⚠️ Warning: Some containers may still be running:"
        echo "$running_containers"
    else
        echo "✅ No demo containers running"
    fi
    
    # Check disk space freed
    if command -v du &> /dev/null; then
        demo_size=$(du -sh . 2>/dev/null | cut -f1)
        echo "📊 Current demo directory size: $demo_size"
    fi
    
    echo "✅ Cleanup verification completed"
}

# Display cleanup summary
show_cleanup_summary() {
    echo ""
    echo "📋 Cleanup Summary:"
    echo "✅ Docker containers stopped and removed"
    echo "✅ Docker volumes cleaned up"
    echo "✅ Log files cleared"
    echo "✅ Temporary files removed"
    echo "✅ Python cache cleared"
    echo ""
    echo "🎯 What was cleaned:"
    echo "   • All serverless-scaling Docker containers"
    echo "   • Associated Docker volumes and networks"
    echo "   • Application log files"
    echo "   • Python bytecode cache files"
    echo "   • Test artifacts and cache"
    echo ""
    echo "💾 What was preserved:"
    echo "   • Source code files"
    echo "   • Configuration files"
    echo "   • Documentation"
    echo ""
}

# Main cleanup process
main() {
    echo "🧹 Serverless Scaling Demo Cleanup Utility"
    echo "=========================================="
    echo ""
    
    # Check if we're in the right directory
    if [[ -d "serverless-scaling-demo" ]]; then
        cd serverless-scaling-demo
    fi
    
    check_demo_directory
    
    echo "🎯 This will clean up the Serverless Scaling demo environment."
    echo "📍 Current directory: $(pwd)"
    echo ""
    
    # Perform cleanup steps
    cleanup_docker
    cleanup_logs
    cleanup_temp_files
    
    echo ""
    echo "🔧 Additional cleanup options:"
    cleanup_docker_system
    reset_demo
    remove_demo_directory
    
    # Verify and summarize
    verify_cleanup
    show_cleanup_summary
    
    echo "🎉 Cleanup completed successfully!"
    echo ""
    echo "💡 To restart the demo:"
    echo "   ./demo.sh"
    echo ""
    echo "📚 To learn more about serverless scaling:"
    echo "   Read the full article in the System Design Interview Roadmap"
    echo ""
}

# Handle script interruption
trap 'echo ""; echo "❌ Cleanup interrupted. Some resources may not be cleaned up."; exit 1' INT TERM

# Run main function
main "$@"