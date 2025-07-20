#!/bin/bash

# Scaling Demonstration Script
# Shows how the system scales under load

set -e

echo "🔄 Serverless Scaling Demonstration"
echo "==================================="
echo ""

# Check if services are running
if ! curl -s http://localhost:8000/ > /dev/null; then
    echo "❌ Services are not running. Please start the demo first:"
    echo "   ./demo.sh"
    exit 1
fi

echo "📊 Current system status:"
curl -s http://localhost/api/status | jq '.' 2>/dev/null || curl -s http://localhost/api/status
echo ""

echo "🛠️ Current worker status:"
curl -s http://localhost:8001/worker/status | jq '.' 2>/dev/null || curl -s http://localhost:8001/worker/status
echo ""

echo "🚀 Phase 1: Creating initial load..."
echo "Creating 20 tasks to fill the queue..."
for i in {1..20}; do
    curl -s -X POST http://localhost/api/task \
        -H 'Content-Type: application/json' \
        -d "{\"type\": \"scale_demo\", \"data\": {\"message\": \"Scale demo task $i\", \"priority\": \"high\"}}" > /dev/null
    echo -n "."
done
echo " Done!"

echo ""
echo "📊 Queue status after creating load:"
curl -s http://localhost/api/metrics | jq '.system_metrics.queue_length' 2>/dev/null || echo "Queue length: Check monitoring dashboard"
echo ""

echo "⏳ Waiting 10 seconds for workers to process some tasks..."
sleep 10

echo ""
echo "🔄 Phase 2: Scaling up workers..."
echo "Scaling from 2 to 4 workers..."
docker-compose up -d --scale worker-service=4

echo "⏳ Waiting 15 seconds for new workers to start..."
sleep 15

echo ""
echo "📊 System status after scaling up:"
curl -s http://localhost:8001/worker/status | jq '.' 2>/dev/null || curl -s http://localhost:8001/worker/status
echo ""

echo "⏳ Waiting 20 seconds to observe improved processing..."
sleep 20

echo ""
echo "📊 Final metrics:"
curl -s http://localhost/api/metrics | jq '.system_metrics' 2>/dev/null || curl -s http://localhost/api/metrics
echo ""

echo "🔄 Phase 3: Scaling down workers..."
echo "Scaling from 4 to 1 worker..."
docker-compose up -d --scale worker-service=1

echo "⏳ Waiting 10 seconds for scaling down..."
sleep 10

echo ""
echo "📊 Final system status:"
curl -s http://localhost:8001/worker/status | jq '.' 2>/dev/null || curl -s http://localhost:8001/worker/status
echo ""

echo "🎯 Scaling demonstration completed!"
echo ""
echo "📊 Monitor the system in real-time:"
echo "   http://localhost:8080"
echo ""
echo "💡 Key observations:"
echo "   • Queue length increases when load exceeds worker capacity"
echo "   • Adding workers reduces queue length and improves throughput"
echo "   • System automatically distributes tasks across available workers"
echo "   • Scaling can be done without downtime"
echo "" 