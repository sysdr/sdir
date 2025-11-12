#!/bin/bash

echo "🧹 Cleaning up Fraud Detection System..."

cd fraud-detection-demo

docker-compose down -v
docker-compose rm -f

cd ..
rm -rf fraud-detection-demo

echo "✅ Cleanup complete!"
