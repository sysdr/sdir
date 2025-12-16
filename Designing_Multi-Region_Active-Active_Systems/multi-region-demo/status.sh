#!/bin/bash

echo "🌍 Multi-Region Active-Active System Status"
echo "==========================================="
echo ""

cd "$(dirname "$0")"

# Check Docker containers
echo "📦 Docker Containers:"
docker-compose ps
echo ""

# Check service health
echo "🏥 Service Health:"
for port in 3001 3002 3003; do
    region=""
    case $port in
        3001) region="us-east" ;;
        3002) region="us-west" ;;
        3003) region="eu-west" ;;
    esac
    if curl -s -f "http://localhost:$port/health" > /dev/null 2>&1; then
        echo "  ✅ $region (port $port): Healthy"
    else
        echo "  ❌ $region (port $port): Unhealthy"
    fi
done

if curl -s -f "http://localhost:3000/" > /dev/null 2>&1; then
    echo "  ✅ Dashboard (port 3000): Accessible"
else
    echo "  ❌ Dashboard (port 3000): Not accessible"
fi
echo ""

# Check metrics
echo "📊 Current Metrics:"
for region in us-east us-west eu-west; do
    case $region in
        us-east) port=3001 ;;
        us-west) port=3002 ;;
        eu-west) port=3003 ;;
    esac
    stats=$(curl -s "http://localhost:$port/stats" 2>/dev/null)
    if [ $? -eq 0 ]; then
        writes=$(echo "$stats" | grep -o '"writes":[0-9]*' | cut -d: -f2 || echo "0")
        replications=$(echo "$stats" | grep -o '"replications":[0-9]*' | cut -d: -f2 || echo "0")
        conflicts=$(echo "$stats" | grep -o '"conflicts":[0-9]*' | cut -d: -f2 || echo "0")
        dataSize=$(echo "$stats" | grep -o '"dataSize":[0-9]*' | cut -d: -f2 || echo "0")
        echo "  $region: Writes=$writes, Replications=$replications, Conflicts=$conflicts, DataSize=$dataSize"
    else
        echo "  $region: Unable to fetch stats"
    fi
done
echo ""

# Check for duplicates
echo "🔍 Duplicate Services Check:"
duplicates=$(docker ps --format "{{.Names}}" | grep -E "(us-east|us-west|eu-west|dashboard)" | sort | uniq -d)
if [ -z "$duplicates" ]; then
    echo "  ✅ No duplicate services found"
else
    echo "  ⚠️  Duplicate services: $duplicates"
fi
echo ""

echo "🌍 Dashboard: http://localhost:3000"
echo "📝 Run './test-dashboard.sh' to test metrics"
echo "🧹 Run './cleanup.sh' to stop and remove all containers"

