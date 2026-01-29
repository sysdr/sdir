#!/bin/bash
cd "$(dirname "$0")" || exit 1
if [ ! -f docker-compose.yml ]; then
  echo "Error: docker-compose.yml not found. Run setup.sh first."
  exit 1
fi
echo "Building Docker images..."
docker-compose build
echo "Build complete."
