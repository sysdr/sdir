#!/bin/bash
echo "🔍 Docker Vector Clock Demo Verification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Determine compose command
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo "1️⃣  Checking Docker containers..."
echo "Container Status:"
$COMPOSE_CMD ps

echo -e "\n2️⃣  Verifying container health..."
healthy_count=0
for i in {0..2}; do
    if response=$(curl -s http://localhost:$((8080 + i))/health 2>/dev/null); then
        echo "✅ Container process-$i: $response"
        ((healthy_count++))
    else
        echo "❌ Container process-$i: Not responding"
    fi
done

echo -e "\n3️⃣  Testing vector clock functionality..."
if [ $healthy_count -eq 3 ]; then
    echo "📨 Sending test message between containers..."
    
    response=$(curl -s -X POST http://localhost:8081/message \
        -H "Content-Type: application/json" \
        -d '{"senderId": 0, "vectorClock": [2,0,0], "content": "Docker verification"}')
    
    if echo "$response" | grep -q "received"; then
        echo "✅ Message exchange successful"
        echo "Response: $response"
    else
        echo "❌ Message exchange failed"
    fi
    
    echo -e "\n📊 Current vector clock states:"
    for i in {0..2}; do
        clock=$(curl -s http://localhost:$((8080 + i))/status | grep -o '"vectorClock":"[^"]*"' | cut -d'"' -f4)
        echo "   Container $i: $clock"
    done
else
    echo "⚠️  Cannot test functionality - not all containers are healthy"
fi

echo -e "\n4️⃣  Checking web interface..."
if curl -s http://localhost:8090 > /dev/null 2>&1; then
    echo "✅ Web interface accessible at http://localhost:8090"
else
    echo "❌ Web interface not accessible"
fi

echo -e "\n5️⃣  Container resource usage..."
echo "Docker Stats (snapshot):"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" \
    vector-clock-process-0 vector-clock-process-1 vector-clock-process-2 vector-clock-web 2>/dev/null || \
    echo "⚠️  Could not retrieve container stats"

echo -e "\n6️⃣  Network connectivity test..."
if docker network inspect vector_clock_docker_demo_vector-clock-network > /dev/null 2>&1; then
    echo "✅ Docker network 'vector-clock-network' exists"
    container_count=$(docker network inspect vector_clock_docker_demo_vector-clock-network | grep -c "vector-clock")
    echo "✅ Network has $container_count connected containers"
else
    echo "❌ Docker network not found"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ $healthy_count -eq 3 ]; then
    echo "✅ Verification complete - All systems operational!"
else
    echo "⚠️  Verification complete - Some issues detected"
fi
echo ""
echo "🔧 Troubleshooting commands:"
echo "   $COMPOSE_CMD logs [service_name]"
echo "   $COMPOSE_CMD restart [service_name]"
echo "   docker system df"
