#!/bin/bash

echo "🔍 Verifying Fault Tolerance vs High Availability Demo"
echo "=================================================="

# Check if services are running
echo "📊 Checking service status..."

# Check Docker containers
echo "🐳 Docker containers:"
if docker ps | grep -q "fault-tolerance-ha-demo"; then
    echo "   ✅ All demo containers are running"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | grep "fault-tolerance-ha-demo"
else
    echo "   ❌ Demo containers not found. Run ./demo.sh first."
    exit 1
fi

echo ""

# Check dashboard accessibility
echo "🌐 Dashboard accessibility:"
if curl -s http://localhost:80 > /dev/null; then
    echo "   ✅ Dashboard accessible at http://localhost:80"
else
    echo "   ❌ Dashboard not accessible"
fi

if curl -s http://localhost:3000 > /dev/null; then
    echo "   ✅ Direct frontend accessible at http://localhost:3000"
else
    echo "   ❌ Direct frontend not accessible"
fi

echo ""

# Check API gateway
echo "🔌 API Gateway:"
if curl -s http://localhost:8080/api/metrics > /dev/null; then
    echo "   ✅ API gateway responding"
    echo "   📈 Current metrics:"
    curl -s http://localhost:8080/api/metrics | jq '.payment.status, .userServices[].status' 2>/dev/null || echo "   (Metrics available but jq not installed)"
else
    echo "   ❌ API gateway not responding"
fi

echo ""

# Test basic functionality
echo "🧪 Testing basic functionality:"

# Test payment service
echo "   💳 Payment service:"
if curl -s -X POST http://localhost:8080/api/payment -H "Content-Type: application/json" -d '{"amount": 100}' > /dev/null; then
    echo "   ✅ Payment service working"
else
    echo "   ❌ Payment service not responding"
fi

# Test user service
echo "   👥 User service:"
if curl -s http://localhost:8080/api/users > /dev/null; then
    echo "   ✅ User service working"
else
    echo "   ❌ User service not responding"
fi

echo ""

echo "🎉 Verification complete!"
echo ""
echo "🌐 Access your demo:"
echo "   Dashboard: http://localhost:80"
echo "   Direct Frontend: http://localhost:3000"
echo "   API Gateway: http://localhost:8080/api/metrics"
echo ""
echo "🎮 Try the 'Verify All' button in the dashboard for comprehensive testing!" 