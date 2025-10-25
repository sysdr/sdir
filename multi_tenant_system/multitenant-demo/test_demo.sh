#!/bin/bash

# Test Multi-Tenant Demo
set -e

echo "🧪 Testing Multi-Tenant System Demo"
echo "=================================="

# Wait for services to be ready
echo "⏳ Ensuring services are ready..."
timeout 30 bash -c 'until curl -s http://localhost:8080/health; do sleep 2; done'

echo "✅ Services are ready, running tests..."
echo ""

cd tests
npm test
cd ..

echo ""
echo "🎉 All tests completed successfully!"
