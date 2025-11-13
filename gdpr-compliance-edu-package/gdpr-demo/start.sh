#!/bin/bash

set -e

echo "🚀 Starting GDPR Compliance Application..."
echo ""

# Check if Docker is installed and running
if ! command -v docker &> /dev/null; then
    echo "❌ Error: Docker is not installed. Please install Docker first."
    exit 1
fi

if ! docker info &> /dev/null; then
    echo "❌ Error: Docker is not running. Please start Docker first."
    exit 1
fi

# Check if docker-compose is available
if command -v docker-compose &> /dev/null; then
    COMPOSE_CMD="docker-compose"
elif docker compose version &> /dev/null; then
    COMPOSE_CMD="docker compose"
else
    echo "❌ Error: docker-compose is not available. Please install docker-compose."
    exit 1
fi

echo "📦 Starting services with Docker Compose..."
echo ""

# Start services in detached mode
$COMPOSE_CMD up -d

echo ""
echo "⏳ Waiting for services to be ready..."
sleep 5

# Check if services are running
echo ""
echo "🔍 Checking service status..."
$COMPOSE_CMD ps

echo ""
echo "✅ Application started successfully!"
echo ""
echo "📍 Services available at:"
echo "   - Frontend:    http://localhost:3000"
echo "   - Backend API: http://localhost:3001"
echo "   - PostgreSQL:  localhost:5432"
echo "   - Redis:       localhost:6379"
echo ""
echo "📊 To view logs, run: $COMPOSE_CMD logs -f"
echo "🛑 To stop services, run: $COMPOSE_CMD down"
echo ""

