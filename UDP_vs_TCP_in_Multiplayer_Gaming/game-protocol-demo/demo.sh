#!/bin/bash

echo "🎮 UDP vs TCP Gaming Demo"
echo "=========================="
echo ""
echo "📊 Dashboard: http://localhost:8080"
echo "📈 Metrics API: http://localhost:3000/metrics"
echo ""
echo "The demo shows:"
echo "  • UDP players (blue) with smooth movement"
echo "  • TCP players (green) with potential freezing"
echo "  • Packet loss simulation (5% and 15%)"
echo "  • Real-time state synchronization"
echo ""
echo "Press Ctrl+C to stop the demo"
echo ""

# Open browser
if command -v open &> /dev/null; then
  open http://localhost:8080
elif command -v xdg-open &> /dev/null; then
  xdg-open http://localhost:8080
fi

# Show logs
docker-compose logs -f game-server
