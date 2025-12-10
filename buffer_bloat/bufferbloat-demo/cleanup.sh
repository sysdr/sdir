#!/bin/bash

echo "🧹 Cleaning up Buffer Bloat demo..."

# Stop traffic generation
docker exec bufferbloat-demo pkill -f generate_traffic.sh 2>/dev/null || true

# Clean up network namespaces
docker exec bufferbloat-demo ip netns delete normal-test 2>/dev/null || true
docker exec bufferbloat-demo ip netns delete bloat-test 2>/dev/null || true
docker exec bufferbloat-demo ip netns delete aqm-test 2>/dev/null || true

# Stop and remove containers
    docker-compose down -v

# Remove created files (optional)
# cd .. && rm -rf bufferbloat-demo

echo "✅ Cleanup complete!"
