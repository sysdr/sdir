#!/bin/bash
echo "🧹 Cleaning up Little's Law demo..."
cd "$(dirname "$0")"
docker compose --profile load down -v --remove-orphans
docker rmi littles-law-demo-api-gateway littles-law-demo-app-server littles-law-demo-load-generator littles-law-demo-dashboard 2>/dev/null || true
echo "✅ Cleanup complete."
