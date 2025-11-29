#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=================================================="
echo "Running Edge Computing Demo - Data Flow Simulation"
echo "=================================================="
echo ""
echo "This script will continuously send data through all tiers"
echo "to keep the dashboard metrics updated."
echo "Press Ctrl+C to stop."
echo ""

# Function to send data through all tiers
send_data_through_tiers() {
    local device_id="device-$((RANDOM % 5 + 1))"
    local temperature=$(awk "BEGIN {printf \"%.1f\", 20 + rand() * 10}")
    local humidity=$(awk "BEGIN {printf \"%.1f\", 40 + rand() * 30}")
    local region="us-west"
    
    # Step 1: Device Edge processing
    local device_result=$(curl -s -X POST http://localhost:3001/process \
        -H "Content-Type: application/json" \
        -d "{\"deviceId\":\"$device_id\",\"temperature\":$temperature,\"humidity\":$humidity,\"region\":\"$region\"}")
    
    if [ $? -ne 0 ] || [ -z "$device_result" ]; then
        echo "Error: Device Edge not responding"
        return 1
    fi
    
    # Step 2: Regional Edge aggregation
    local regional_result=$(curl -s -X POST http://localhost:3002/aggregate \
        -H "Content-Type: application/json" \
        -d "$device_result")
    
    if [ $? -ne 0 ] || [ -z "$regional_result" ]; then
        echo "Error: Regional Edge not responding"
        return 1
    fi
    
    # Step 3: Central Cloud storage
    local cloud_result=$(curl -s -X POST http://localhost:3003/store \
        -H "Content-Type: application/json" \
        -d "$regional_result")
    
    if [ $? -ne 0 ]; then
        echo "Error: Central Cloud not responding"
        return 1
    fi
    
    echo "✓ Data processed: $device_id (Temp: ${temperature}°C, Humidity: ${humidity}%)"
    return 0
}

# Check if services are running
echo "Checking if services are running..."
for port in 3001 3002 3003; do
    if ! curl -s http://localhost:$port/health > /dev/null; then
        echo "Error: Service on port $port is not responding"
        echo "Please run ./start.sh first to start the services"
        exit 1
    fi
done

echo "All services are healthy. Starting data flow simulation..."
echo ""

# Continuous data flow
counter=0
while true; do
    counter=$((counter + 1))
    send_data_through_tiers
    
    # Every 10 iterations, show current metrics
    if [ $((counter % 10)) -eq 0 ]; then
        echo ""
        echo "--- Current Metrics (after $counter iterations) ---"
        echo "Device Edge - Processed: $(curl -s http://localhost:3001/metrics | grep -o '"processed":[0-9]*' | cut -d: -f2)"
        echo "Regional Edge - Aggregated: $(curl -s http://localhost:3002/metrics | grep -o '"aggregated":[0-9]*' | cut -d: -f2)"
        echo "Central Cloud - Stored: $(curl -s http://localhost:3003/metrics | grep -o '"stored":[0-9]*' | cut -d: -f2)"
        echo ""
    fi
    
    sleep 3
done

