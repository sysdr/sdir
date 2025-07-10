#!/bin/bash
set -e

echo "Building data streaming architecture demo..."

# Build Docker images
docker-compose build --no-cache

echo "Build complete!"
