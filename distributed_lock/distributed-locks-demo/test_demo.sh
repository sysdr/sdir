#!/bin/bash

echo "🧪 Running Distributed Locking Tests"
echo "===================================="

# Ensure services are running
docker-compose up -d
sleep 5

# Run the test suite
echo "Running unit tests..."
docker-compose exec demo-app python -m pytest tests/ -v --tb=short

# Test the basic lock mechanisms directly
echo ""
echo "Testing lock mechanisms directly..."
docker-compose exec demo-app python src/lock_mechanisms.py

echo ""
echo "✅ All tests completed!"
