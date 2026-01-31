#!/bin/bash

echo "🎯 Kappa vs Lambda Architecture Demo"
echo ""
echo "Dashboard: http://localhost:3000"
echo ""
echo "Watch the metrics update in real-time:"
echo "- Lambda shows drift between batch and speed layers"
echo "- Kappa maintains consistency with single processing"
echo ""
echo "Try triggering a Kappa replay from the dashboard!"
echo ""
echo "Press Ctrl+C to stop watching logs..."
docker-compose logs -f dashboard lambda-batch lambda-speed kappa-processor
