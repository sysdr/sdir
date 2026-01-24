#!/bin/bash

echo "🔍 Validating UDP vs TCP Gaming Demo..."
echo ""

# Check if services are running
echo "1. Checking Docker services..."
if docker ps | grep -q "game-server\|game-clients\|game-dashboard"; then
    echo "   ✅ Docker services are running"
    docker ps --filter "name=game-" --format "   {{.Names}}: {{.Status}}"
else
    echo "   ❌ No Docker services found"
    exit 1
fi

echo ""
echo "2. Checking metrics endpoint..."
METRICS=$(curl -s http://localhost:3000/metrics 2>/dev/null)
if [ $? -eq 0 ] && [ ! -z "$METRICS" ]; then
    echo "   ✅ Metrics endpoint is accessible"
    
    # Parse metrics
    UDP_SENT=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['metrics']['udpPacketsSent'])" 2>/dev/null)
    TCP_SENT=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['metrics']['tcpPacketsSent'])" 2>/dev/null)
    UDP_RECV=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['metrics']['udpPacketsReceived'])" 2>/dev/null)
    TCP_RECV=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['metrics']['tcpPacketsReceived'])" 2>/dev/null)
    CONNECTIONS=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['metrics']['activeConnections'])" 2>/dev/null)
    TICK=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['tickNumber'])" 2>/dev/null)
    PLAYERS=$(echo "$METRICS" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d['playerCount'])" 2>/dev/null)
    
    echo ""
    echo "   📊 Current Metrics:"
    echo "      UDP Packets Sent: $UDP_SENT $([ $UDP_SENT -gt 0 ] && echo '✅' || echo '❌')"
    echo "      TCP Packets Sent: $TCP_SENT $([ $TCP_SENT -gt 0 ] && echo '✅' || echo '❌')"
    echo "      UDP Packets Received: $UDP_RECV $([ $UDP_RECV -gt 0 ] && echo '✅' || echo '❌')"
    echo "      TCP Packets Received: $TCP_RECV $([ $TCP_RECV -gt 0 ] && echo '✅' || echo '❌')"
    echo "      Active Connections: $CONNECTIONS $([ $CONNECTIONS -gt 0 ] && echo '✅' || echo '❌')"
    echo "      Tick Number: $TICK $([ $TICK -gt 0 ] && echo '✅' || echo '❌')"
    echo "      Player Count: $PLAYERS $([ $PLAYERS -gt 0 ] && echo '✅' || echo '❌')"
    
    # Check if all metrics are non-zero
    if [ $UDP_SENT -gt 0 ] && [ $TCP_SENT -gt 0 ] && [ $UDP_RECV -gt 0 ] && [ $TCP_RECV -gt 0 ] && [ $CONNECTIONS -gt 0 ] && [ $TICK -gt 0 ] && [ $PLAYERS -gt 0 ]; then
        echo ""
        echo "   ✅ All metrics are updating correctly!"
    else
        echo ""
        echo "   ⚠️  Some metrics are zero - demo may need more time to initialize"
    fi
else
    echo "   ❌ Metrics endpoint not accessible"
    exit 1
fi

echo ""
echo "3. Checking dashboard..."
if curl -s http://localhost:8080 | grep -q "UDP vs TCP"; then
    echo "   ✅ Dashboard is accessible at http://localhost:8080"
else
    echo "   ❌ Dashboard not accessible"
    exit 1
fi

echo ""
echo "4. Checking for duplicate services..."
DUPLICATES=$(ps aux | grep -E "node.*gameServer|node.*gameClient" | grep -v grep | wc -l)
if [ $DUPLICATES -eq 0 ]; then
    echo "   ✅ No duplicate services running (all services are in Docker)"
else
    echo "   ⚠️  Found $DUPLICATES duplicate service(s) running outside Docker"
fi

echo ""
echo "5. Checking startup scripts..."
if [ -f "demo.sh" ] && [ -x "demo.sh" ]; then
    echo "   ✅ demo.sh exists and is executable"
else
    echo "   ❌ demo.sh missing or not executable"
fi

if [ -f "cleanup.sh" ] && [ -x "cleanup.sh" ]; then
    echo "   ✅ cleanup.sh exists and is executable"
else
    echo "   ❌ cleanup.sh missing or not executable"
fi

echo ""
echo "✅ Validation complete!"
echo ""
echo "📊 Dashboard: http://localhost:8080"
echo "📈 Metrics API: http://localhost:3000/metrics"
echo ""
echo "To view logs: docker-compose logs -f"
echo "To run demo: bash demo.sh"
echo "To cleanup: bash cleanup.sh"

