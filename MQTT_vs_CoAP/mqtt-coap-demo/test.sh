#!/bin/bash

echo "Running protocol comparison tests..."

# Test MQTT connectivity
echo "Testing MQTT service..."
response=$(curl -s http://localhost:3001/metrics)
if [ $? -eq 0 ]; then
  echo "✓ MQTT service is responding"
else
  echo "✗ MQTT service failed"
  exit 1
fi

# Test CoAP connectivity
echo "Testing CoAP service..."
response=$(curl -s http://localhost:3002/metrics)
if [ $? -eq 0 ]; then
  echo "✓ CoAP service is responding"
else
  echo "✗ CoAP service failed"
  exit 1
fi

# Test Dashboard
echo "Testing Dashboard..."
response=$(curl -s http://localhost:3000)
if [ $? -eq 0 ]; then
  echo "✓ Dashboard is responding"
else
  echo "✗ Dashboard failed"
  exit 1
fi

echo ""
echo "All tests passed! ✓"
