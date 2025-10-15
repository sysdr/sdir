#!/bin/bash

echo "🧹 Cleaning up Monitoring & Alerting Demo..."

docker compose down -v
docker system prune -f
docker volume prune -f

echo "✅ Cleanup completed!"
