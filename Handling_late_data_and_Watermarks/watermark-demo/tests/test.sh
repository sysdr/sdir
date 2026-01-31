#!/bin/bash

echo "Running Watermark Demo Tests..."

# Test 1: Producer health
echo "Test 1: Producer health check..."
HEALTH=$(curl -s http://localhost:3000/health | grep -o "healthy")
if [ "$HEALTH" = "healthy" ]; then
    echo "✓ Producer is healthy"
else
    echo "✗ Producer health check failed"
    exit 1
fi

# Test 2: Processor health
echo "Test 2: Processor health check..."
HEALTH=$(curl -s http://localhost:3001/health | grep -o "healthy")
if [ "$HEALTH" = "healthy" ]; then
    echo "✓ Processor is healthy"
else
    echo "✗ Processor health check failed"
    exit 1
fi

# Test 3: Wait for events to flow
echo "Test 3: Waiting for events to process..."
sleep 15

# Test 4: Verify processor is processing events
echo "Test 4: Checking processor stats..."
STATS=$(curl -s http://localhost:3001/stats)
WINDOW_COUNT=$(echo $STATS | grep -o '"activeWindows":[0-9]*' | grep -o '[0-9]*')

if [ ! -z "$WINDOW_COUNT" ]; then
    echo "✓ Processor has active windows: $WINDOW_COUNT"
else
    echo "✗ No active windows found"
    exit 1
fi

# Test 5: Dashboard accessibility
echo "Test 5: Dashboard accessibility..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3002)
if [ "$HTTP_CODE" = "200" ]; then
    echo "✓ Dashboard is accessible"
else
    echo "✗ Dashboard returned HTTP $HTTP_CODE"
    exit 1
fi

# Test 6: Verify metrics for dashboard (non-zero so dashboard updates with demo)
echo "Test 6: Verifying metrics for dashboard..."
TOTAL_EVENTS=$(echo "$STATS" | grep -o '"totalEvents":[0-9]*' | head -1 | grep -o '[0-9]*')
WATERMARK=$(echo "$STATS" | grep -o '"watermark":[0-9]*' | grep -o '[0-9]*')
if [ -n "$WATERMARK" ] && [ "$WATERMARK" -gt 0 ] && [ -n "$WINDOW_COUNT" ] && [ "$WINDOW_COUNT" -gt 0 ]; then
    echo "✓ Dashboard metrics will update (watermark and $WINDOW_COUNT windows with events)"
else
    echo "✗ Processor metrics not ready for dashboard (watermark=$WATERMARK, windows=$WINDOW_COUNT)"
    exit 1
fi

echo ""
echo "================================"
echo "All tests passed! ✓"
echo "================================"
