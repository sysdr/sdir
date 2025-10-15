#!/bin/bash

PROJECT_NAME="geospatial-demo"

case "$1" in
  "setup"|"")
    echo "🌍 Building Geospatial System Demo..."
    docker-compose build --no-cache
    echo "✅ Build completed!"
    echo ""
    echo "🚀 Starting services..."
    docker-compose up -d
    echo ""
    echo "⏳ Waiting for services to initialize..."
    sleep 45
    echo ""
    echo "🧪 Running tests..."
    ./scripts/test.sh
    echo ""
    echo "🎉 Geospatial System Demo is ready!"
    echo ""
    echo "📊 Access Points:"
    echo "  • Main Dashboard: http://localhost:3000"
    echo "  • Location Service API: http://localhost:8000"
    echo "  • Geofence Service API: http://localhost:8003"
    echo "  • Proximity Service API: http://localhost:8002"
    echo "  • Redis Dashboard: http://localhost:8001"
    echo ""
    echo "🎯 Try these features:"
    echo "  • Real-time driver tracking on the map"
    echo "  • Proximity search with adjustable radius"
    echo "  • K-nearest neighbor queries"
    echo "  • Geofence boundary checking"
    echo "  • Performance metrics visualization"
    echo ""
    echo "🔧 To stop: ./cleanup.sh"
    ;;
  "start")
    docker-compose up -d
    echo "✅ Services started!"
    ;;
  "stop")
    docker-compose down
    echo "✅ Services stopped!"
    ;;
  "logs")
    docker-compose logs -f ${2:-}
    ;;
  "test")
    ./scripts/test.sh
    ;;
  *)
    echo "Usage: $0 {setup|start|stop|logs|test}"
    echo ""
    echo "Commands:"
    echo "  setup  - Build and start the complete demo"
    echo "  start  - Start existing services"
    echo "  stop   - Stop all services"
    echo "  logs   - Show service logs"
    echo "  test   - Run functionality tests"
    ;;
esac
