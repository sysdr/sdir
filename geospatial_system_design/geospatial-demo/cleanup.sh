#!/bin/bash

echo "🧹 Cleaning up Geospatial System Demo..."

# Stop and remove containers
docker-compose down -v --remove-orphans

# Remove images
docker rmi $(docker images -f "dangling=true" -q) 2>/dev/null || true
docker rmi ${PROJECT_NAME}_location-service 2>/dev/null || true
docker rmi ${PROJECT_NAME}_geofence-service 2>/dev/null || true
docker rmi ${PROJECT_NAME}_proximity-service 2>/dev/null || true
docker rmi ${PROJECT_NAME}_web-dashboard 2>/dev/null || true

# Remove volumes
docker volume rm ${PROJECT_NAME}_redis_data 2>/dev/null || true
docker volume rm ${PROJECT_NAME}_postgres_data 2>/dev/null || true

echo "✅ Cleanup completed!"
echo ""
echo "To rebuild: ./demo.sh setup"
