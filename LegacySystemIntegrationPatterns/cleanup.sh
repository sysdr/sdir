#!/bin/bash

echo "Stopping and removing all containers..."
cd legacy-integration-demo
docker-compose down -v

echo "Cleaning up..."
cd ..
rm -rf legacy-integration-demo

echo "✅ Cleanup complete!"
