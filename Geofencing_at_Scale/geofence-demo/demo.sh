#!/bin/bash

echo "🚀 Starting Geofencing Demo..."
docker-compose up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 5

echo ""
echo "✅ Demo is running!"
echo ""
echo "📍 Access the dashboard at: http://localhost:8080"
echo "🔌 API available at: http://localhost:3000"
echo ""
echo "Press Ctrl+C to stop watching logs..."
docker-compose logs -f
