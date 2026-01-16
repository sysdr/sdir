#!/bin/bash

echo "=================================================="
echo "Real-Time Analytics Demo"
echo "=================================================="

echo ""
echo "📊 Dashboard: http://localhost:3000"
echo ""
echo "Generate traffic:"
echo "  curl -X POST http://localhost:3001/generate-load -H 'Content-Type: application/json' -d '{\"count\": 1000, \"ratePerSecond\": 100}'"
echo ""
echo "Query current metrics:"
echo "  curl http://localhost:3002/metrics/current | jq"
echo ""
echo "View processing logs:"
echo "  docker-compose logs -f processor"
echo ""
echo "Press Ctrl+C to exit"

# Keep script running
tail -f /dev/null
