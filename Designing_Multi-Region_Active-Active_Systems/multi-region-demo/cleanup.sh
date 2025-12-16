#!/bin/bash

echo "🧹 Cleaning up Multi-Region Demo..."
docker-compose down -v
cd ..
rm -rf multi-region-demo
echo "✓ Cleanup complete"
