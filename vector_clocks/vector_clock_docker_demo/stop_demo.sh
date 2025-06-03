#!/bin/bash
echo "🛑 Stopping Docker Vector Clock Demo..."

# Determine compose command
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo "📊 Final container status:"
$COMPOSE_CMD ps

echo "🗂️  Collecting final logs..."
mkdir -p logs_archive/$(date +"%Y%m%d_%H%M%S")
$COMPOSE_CMD logs > logs_archive/$(date +"%Y%m%d_%H%M%S")/all_containers.log 2>&1

echo "🧹 Stopping and removing containers..."
$COMPOSE_CMD down --remove-orphans

echo "🔍 Cleaning up unused Docker resources..."
docker system prune -f > /dev/null 2>&1

echo "✅ Docker demo stopped successfully"
echo "📁 Logs archived in logs_archive/"
