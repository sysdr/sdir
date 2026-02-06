#!/bin/bash

echo "🎯 Running Locking Demo..."
echo ""
echo "The demo is now running at:"
echo "📊 Dashboard: http://localhost:3000"
echo "🔧 API: http://localhost:3001"
echo ""
echo "Try the following:"
echo "1. Click 'Run 100 Pessimistic Transactions' to see blocking behavior"
echo "2. Click 'Run 100 Optimistic Transactions' to see retry behavior"
echo "3. Compare average lock wait times vs retry counts"
echo "4. Notice how pessimistic locking has consistent latency"
echo "5. Notice how optimistic locking has variable latency due to retries"
echo ""
echo "Press Ctrl+C to stop the demo"
docker-compose logs -f
