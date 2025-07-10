#!/bin/bash
set -e

echo "Cleaning up data streaming demo..."

# Stop and remove containers
docker-compose down -v

# Remove Docker images
docker-compose down --rmi all

# Remove volumes
docker volume prune -f

# Remove logs
rm -rf logs/*

echo "Cleanup complete!"
