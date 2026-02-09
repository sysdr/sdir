#!/bin/bash
# Live Streaming Demo - Cleanup Script
# Stops all containers and removes unused Docker resources

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "🧹 Live Streaming - Full Cleanup"
echo "================================"

# Stop ffmpeg stream container if running
echo "Stopping ffmpeg stream..."
docker stop ffmpeg-stream 2>/dev/null || true

# Stop and remove project containers
echo "Stopping streaming-demo containers..."
docker compose down -v 2>/dev/null || true

# Stop all running containers
echo "Stopping all containers..."
docker stop $(docker ps -aq) 2>/dev/null || true

# Remove project-specific images
echo "Removing project images..."
docker rmi streaming-demo-transcoder streaming-demo-hls-server streaming-demo-dashboard streaming-demo-ingest 2>/dev/null || true

# Remove dangling images
echo "Removing dangling images..."
docker image prune -f

# Remove stopped containers
echo "Removing stopped containers..."
docker container prune -f

# Remove unused networks
echo "Removing unused networks..."
docker network prune -f

# Remove unused volumes
echo "Removing unused volumes..."
docker volume prune -f

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Docker status:"
docker ps -a 2>/dev/null || true
