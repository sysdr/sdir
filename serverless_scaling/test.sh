#!/bin/bash

# Test script for Serverless Scaling Demo

set -e

echo "🧪 Testing Serverless Scaling Demo..."
echo "====================================="
echo ""

# Check if services are running
echo "🔍 Checking if services are running..."

# Test API Gateway
echo "Testing API Gateway..."
if curl -s http://localhost:8000/ > /dev/null; then
    echo "✅ API Gateway is responding"
else
    echo "❌ API Gateway is not responding"
    exit 1
fi

# Test Load Balancer
echo "Testing Load Balancer..."
if curl -s http://localhost/ > /dev/null; then
    echo "✅ Load Balancer is responding"
else
    echo "❌ Load Balancer is not responding"
    exit 1
fi

# Test Monitoring Dashboard
echo "Testing Monitoring Dashboard..."
if curl -s http://localhost:8080/ > /dev/null; then
    echo "✅ Monitoring Dashboard is responding"
else
    echo "❌ Monitoring Dashboard is not responding"
    exit 1
fi

echo ""
echo "📊 Testing API endpoints..."

# Test system status
echo "Testing system status..."
STATUS_RESPONSE=$(curl -s http://localhost/api/status)
if echo "$STATUS_RESPONSE" | grep -q "api_gateway"; then
    echo "✅ System status endpoint working"
else
    echo "❌ System status endpoint failed"
    echo "Response: $STATUS_RESPONSE"
fi

# Test task creation
echo "Testing task creation..."
TASK_RESPONSE=$(curl -s -X POST http://localhost/api/task \
  -H 'Content-Type: application/json' \
  -d '{"type": "test", "data": {"message": "Test task"}}')

if echo "$TASK_RESPONSE" | grep -q "task_id"; then
    echo "✅ Task creation working"
    TASK_ID=$(echo "$TASK_RESPONSE" | grep -o '"task_id":"[^"]*"' | cut -d'"' -f4)
    echo "   Created task: $TASK_ID"
else
    echo "❌ Task creation failed"
    echo "Response: $TASK_RESPONSE"
fi

# Test metrics endpoint
echo "Testing metrics endpoint..."
METRICS_RESPONSE=$(curl -s http://localhost/api/metrics)
if echo "$METRICS_RESPONSE" | grep -q "system_metrics"; then
    echo "✅ Metrics endpoint working"
else
    echo "❌ Metrics endpoint failed"
    echo "Response: $METRICS_RESPONSE"
fi

# Test worker status
echo "Testing worker status..."
WORKER_RESPONSE=$(curl -s http://localhost:8001/worker/status)
if echo "$WORKER_RESPONSE" | grep -q "worker_id"; then
    echo "✅ Worker status endpoint working"
else
    echo "❌ Worker status endpoint failed"
    echo "Response: $WORKER_RESPONSE"
fi

echo ""
echo "🎯 Demo is working correctly!"
echo ""
echo "📊 Access the monitoring dashboard: http://localhost:8080"
echo "🔗 API documentation: http://localhost:8000/docs"
echo ""
echo "🧪 To run load testing:"
echo "   docker-compose --profile load-test up load-test"
echo ""
echo "🔄 To scale workers:"
echo "   docker-compose up -d --scale worker-service=3" 