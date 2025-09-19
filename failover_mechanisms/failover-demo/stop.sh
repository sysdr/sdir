#!/bin/bash

echo "🛑 Stopping Failover Mechanisms Demo..."

# Stop and remove containers
docker-compose down

echo "✅ Demo stopped successfully!"
echo ""
echo "📋 To restart the demo:"
echo "   ./demo.sh"
echo ""
echo "🧹 To clean up everything:"
echo "   ./cleanup.sh"
