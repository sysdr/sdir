#!/bin/bash

echo "🚀 Starting SLA Design Demo..."

# Build and start services
docker-compose up -d --build

echo "⏳ Waiting for services to be ready..."
sleep 15

# Check if services are running
if curl -s http://localhost:3000/api/sla-status > /dev/null; then
    echo "✅ Demo is ready!"
    echo ""
    echo "🌐 Access the demo at: http://localhost:3000"
    echo ""
    echo "📊 Features:"
    echo "  • Multi-tier SLA monitoring (Premium/Standard/Basic)"
    echo "  • Real-time error budget tracking"
    echo "  • Service performance metrics"
    echo "  • Load testing capabilities"
    echo ""
    echo "🧪 Try these scenarios:"
    echo "  1. Switch between Premium, Standard, and Basic tiers"
    echo "  2. Use 'Send Test Request' to trigger individual requests"
    echo "  3. Use 'Generate Load' to stress test services"
    echo "  4. Watch error budgets deplete during failures"
    echo ""
    echo "📈 Monitoring:"
    echo "  • Availability percentages"
    echo "  • P95 latency measurements"
    echo "  • Error budget consumption"
    echo "  • SLA breach alerts"
else
    echo "❌ Demo failed to start. Check logs with: docker-compose logs"
    exit 1
fi
