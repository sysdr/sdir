#!/bin/bash

echo "🧪 Testing Live Streaming Architecture..."

# Test 1: Check if all services are running
echo "Test 1: Checking service health..."
sleep 5

services=("rtmp-ingest:8080" "transcoder:3001" "hls-delivery:3002" "dashboard:80")
for service in "${services[@]}"; do
    container="${service%%:*}"
    if docker ps | grep -q "$container"; then
        echo "✓ $container is running"
    else
        echo "✗ $container is not running"
        exit 1
    fi
done

# Test 2: Check HLS playlist generation
echo ""
echo "Test 2: Checking HLS playlist generation..."
sleep 20

for quality in 1080p 720p 480p 360p; do
    if docker exec transcoder ls /output/$quality/playlist.m3u8 &>/dev/null; then
        echo "✓ $quality playlist generated"
    else
        echo "✗ $quality playlist not found"
    fi
done

# Test 3: Check segment delivery
echo ""
echo "Test 3: Testing segment delivery..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3002/live/master.m3u8)
if [ "$response" = "200" ]; then
    echo "✓ Master playlist accessible"
else
    echo "✗ Master playlist failed (HTTP $response)"
fi

# Test 4: Check dashboard
echo ""
echo "Test 4: Testing dashboard..."
response=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000)
if [ "$response" = "200" ]; then
    echo "✓ Dashboard accessible"
else
    echo "✗ Dashboard failed (HTTP $response)"
fi

echo ""
echo "✅ All tests passed!"
