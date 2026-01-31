#!/bin/bash

echo "🎬 Starting Windowing Strategies Demo..."
echo ""
echo "📊 Dashboard: http://localhost:3000"
echo "🔌 Backend API: http://localhost:3001"
echo ""
echo "The dashboard shows three windowing strategies processing the same event stream:"
echo "  • Tumbling Windows: 1-minute non-overlapping buckets"
echo "  • Sliding Windows: 5-minute windows sliding every 15 seconds"
echo "  • Session Windows: Activity-based windows with 30-second inactivity gap"
echo ""
echo "Watch how the same stock trading events produce different insights!"
echo ""
echo "Press Ctrl+C to stop the demo"

docker-compose logs -f
