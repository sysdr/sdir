#!/bin/bash

echo "🚀 Starting Instagram Sharding Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Build and start services
echo "🔧 Building Docker containers..."
docker-compose build

echo "🌟 Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "⏳ Waiting for services to be ready..."
sleep 10

# Run tests
echo "🧪 Running tests..."
docker-compose exec app pytest tests/ -v

# Show access information
echo ""
echo "✅ Instagram Sharding Demo is ready!"
echo "🌐 Access the demo at: http://localhost:5000"
echo "📊 API endpoint: http://localhost:5000/api/stats"
echo ""
echo "🎯 Demo Features:"
echo "   • Interactive shard visualization"
echo "   • User creation and routing"
echo "   • Hot shard simulation"
echo "   • Load distribution analysis"
echo ""
echo "📋 Commands:"
echo "   • View logs: docker-compose logs -f"
echo "   • Stop demo: ./cleanup.sh"
echo ""
