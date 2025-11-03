#!/bin/bash

echo "🧹 Cleaning up CI/CD Demo..."

# Stop and remove containers
docker-compose down -v --remove-orphans

# Remove dangling images
docker image prune -f

# Remove project-specific images
docker images | grep cicd- | awk '{print $3}' | xargs -r docker rmi -f

echo "✅ Cleanup completed!"
