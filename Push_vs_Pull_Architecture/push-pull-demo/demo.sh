#!/bin/bash

echo "=== Push vs Pull Architecture Demo ==="
echo ""
echo "Opening dashboard at http://localhost:8080"
echo ""
echo "What you'll see:"
echo "- PUSH: Real-time WebSocket updates (instant delivery)"
echo "- PULL: Polling-based updates (1-second intervals)"
echo "- Live metrics comparing both approaches"
echo ""
echo "Press Ctrl+C to stop watching logs"
echo ""

# Open browser
if command -v xdg-open > /dev/null; then
  xdg-open http://localhost:8080
elif command -v open > /dev/null; then
  open http://localhost:8080
fi

# Show logs
docker-compose -f push-pull-demo/docker-compose.yml logs -f
