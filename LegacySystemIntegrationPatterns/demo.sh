#!/bin/bash

set -e

echo "=========================================="
echo "Building Docker images..."
echo "=========================================="
cd legacy-integration-demo
docker-compose build

echo ""
echo "=========================================="
echo "Starting services..."
echo "=========================================="
docker-compose up -d

echo ""
echo "Waiting for services to be ready..."
sleep 15

echo ""
echo "=========================================="
echo "✅ Demo is ready!"
echo "=========================================="
echo ""
echo "🌐 Dashboard: http://localhost:3100"
echo "🔄 Strangler Proxy: http://localhost:3000"
echo "📊 ACL Stats: http://localhost:3005/acl/stats"
echo "🏪 Products API: http://localhost:3000/api/products"
echo ""
echo "=========================================="
echo "Try these experiments:"
echo "=========================================="
echo "1. Open dashboard and click 'Create Test Order' multiple times"
echo "2. Adjust the 'Modern Traffic %' slider to see routing change"
echo "3. Watch latency differences between Legacy and Modern routes"
echo "4. Observe ACL cache hit rate improving over time"
echo "5. Set Modern Traffic to 100% to complete strangler pattern"
echo ""
echo "Service Logs:"
echo "  docker-compose logs -f strangler-proxy"
echo "  docker-compose logs -f acl-service"
echo "  docker-compose logs -f legacy-service"
echo ""
echo "To clean up, run: ./cleanup.sh"
