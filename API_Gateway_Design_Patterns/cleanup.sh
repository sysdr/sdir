#!/bin/bash

echo "Cleaning up API Gateway Demo..."
echo "======================================"

if [ -d "api-gateway-demo" ]; then
  cd api-gateway-demo
  echo "Stopping Docker containers..."
  docker-compose down -v 2>/dev/null || true
  cd ..
fi

echo "Removing generated files..."
rm -rf api-gateway-demo

echo "Checking for running containers..."
RUNNING=$(docker ps --filter "name=api-gateway-demo" -q)
if [ ! -z "$RUNNING" ]; then
  echo "Stopping remaining containers..."
  docker stop $RUNNING 2>/dev/null || true
  docker rm $RUNNING 2>/dev/null || true
fi

echo "✅ Cleanup complete!"


