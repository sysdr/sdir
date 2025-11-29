#!/bin/bash

set -e

echo "🚀 Starting Mobile Backend Demo"
echo "================================"

cd mobile-backend-demo

echo ""
echo "📦 Building Docker containers..."
docker-compose build

echo ""
echo "🚀 Starting services..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 15

echo ""
echo "🧪 Running tests..."
bash tests/test.sh

echo ""
echo "✅ Demo Setup Complete!"
echo ""
echo "📊 Access Points:"
echo "   Dashboard:    http://localhost:8080"
echo "   API Gateway:  http://localhost:3000"
echo "   Sync Service: http://localhost:3001"
echo "   Queue Status: http://localhost:3002"
echo ""
echo "🎯 Try These Actions:"
echo "   1. Open dashboard and click 'Simulate Offline Write'"
echo "   2. Click 'Disconnect' to simulate offline mode"
echo "   3. Create multiple writes while offline"
echo "   4. Click 'Reconnect' to see sync in action"
echo "   5. Watch metrics update in real-time"
echo ""
echo "📝 View logs: docker-compose logs -f"
echo "🧹 Cleanup: ./cleanup.sh"
