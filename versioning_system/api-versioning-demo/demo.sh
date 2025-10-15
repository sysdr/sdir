#!/bin/bash

echo "🚀 Starting API Versioning Demo..."

# Install dependencies
echo "📦 Installing dependencies..."
npm install

# Run tests
echo "🧪 Running tests..."
npm test

# Start the application
echo "🌐 Starting application..."
if command -v docker-compose &> /dev/null; then
    docker-compose up -d
    echo "✅ Demo running with Docker Compose"
    echo "🌐 Dashboard: http://localhost:3000"
    echo "📊 Prometheus: http://localhost:9090"
else
    npm start &
    echo "✅ Demo running locally"
    echo "🌐 Dashboard: http://localhost:3000"
fi

echo ""
echo "🎯 Try these examples:"
echo "curl http://localhost:3000/api/v1/users"
echo "curl -H 'API-Version: 2' http://localhost:3000/api/users"
echo "curl -H 'Accept: application/json;version=3' http://localhost:3000/api/users"
echo ""
echo "📱 Open http://localhost:3000 for interactive demo"
