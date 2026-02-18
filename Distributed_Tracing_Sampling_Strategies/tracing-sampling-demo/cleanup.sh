#!/bin/bash
echo "Stopping and removing containers..."
docker compose down -v --remove-orphans 2>/dev/null || docker-compose down -v --remove-orphans 2>/dev/null
echo "Removing built images..."
docker rmi tracing-sampling-demo-collector tracing-sampling-demo-generator 2>/dev/null || true
echo "Cleaned up."
