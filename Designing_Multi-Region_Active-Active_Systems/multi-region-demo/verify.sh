#!/bin/bash

echo "🔍 Verifying Multi-Region System..."
echo "===================================="

# Check if docker-compose services are running
echo ""
echo "1. Checking Docker containers..."
cd "$(dirname "$0")"
docker-compose ps

# Check for duplicate services
echo ""
echo "2. Checking for duplicate services..."
DUPLICATES=$(docker ps --format "{{.Names}}" | grep -E "(us-east|us-west|eu-west|dashboard)" | sort | uniq -d)
if [ -z "$DUPLICATES" ]; then
    echo "✅ No duplicate services found"
else
    echo "⚠️  Duplicate services found: $DUPLICATES"
fi

# Check if services are responding
echo ""
echo "3. Checking service health..."
for port in 3001 3002 3003; do
    if curl -s -f "http://localhost:$port/health" > /dev/null 2>&1; then
        echo "✅ Port $port is responding"
    else
        echo "❌ Port $port is not responding"
    fi
done

# Check dashboard
if curl -s -f "http://localhost:3000/" > /dev/null 2>&1; then
    echo "✅ Dashboard (port 3000) is responding"
else
    echo "❌ Dashboard (port 3000) is not responding"
fi

# Run tests
echo ""
echo "4. Running tests..."
node test.js

echo ""
echo "✅ Verification complete!"

