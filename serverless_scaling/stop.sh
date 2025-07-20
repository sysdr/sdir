#!/bin/bash

# Serverless Scaling Demo - Stop Script
# System Design Interview Roadmap - Issue #101

set -e

echo "🛑 Stopping Serverless Scaling Demo..."
echo "======================================"
echo ""

# Check if we're in the right directory
if [[ ! -f "docker-compose.yml" ]] || [[ ! -d "src" ]]; then
    echo "❌ This doesn't appear to be the serverless scaling demo directory."
    echo "Please run this script from the demo directory."
    exit 1
fi

# Check if services are running
if ! docker-compose ps | grep -q "Up"; then
    echo "ℹ️  No services are currently running."
    echo "💡 To start the demo, run: ./start.sh"
    exit 0
fi

echo "📊 Current service status:"
docker-compose ps
echo ""

# Show what will be stopped
echo "🔍 Services that will be stopped:"
docker-compose ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" | grep "Up" || true
echo ""

# Ask for confirmation
read -p "Are you sure you want to stop all services? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "⏭️  Operation cancelled. Services remain running."
    exit 0
fi

echo "🔄 Stopping services..."
docker-compose down

echo ""
echo "✅ All services stopped successfully!"
echo ""
echo "📊 Final status:"
docker-compose ps
echo ""
echo "💡 To restart the demo:"
echo "   ./start.sh"
echo ""
echo "🧹 To clean up everything (including volumes):"
echo "   ./setup.sh"
echo ""
echo "👋 Demo stopped successfully!" 