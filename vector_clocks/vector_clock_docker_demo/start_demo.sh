#!/bin/bash
echo "🐳 Starting Dockerized Vector Clock Demo..."

# Check Docker and Docker Compose
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

if ! command -v docker-compose &> /dev/null && ! docker compose version &> /dev/null 2>&1; then
    echo "❌ Docker Compose is not available. Please install Docker Compose."
    exit 1
fi

# Use docker compose (newer) or docker-compose (legacy)
if docker compose version &> /dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
else
    COMPOSE_CMD="docker-compose"
fi

echo "🧹 Cleaning up existing containers..."
$COMPOSE_CMD down --remove-orphans 2>/dev/null || true

echo "🔨 Building Docker images..."
$COMPOSE_CMD build --no-cache

echo "🚀 Starting services..."
$COMPOSE_CMD up -d

echo "⏳ Waiting for services to be healthy..."
sleep 5

# Check service health
echo "🔍 Checking service status..."
healthy=0
for i in {0..2}; do
    if curl -s http://localhost:$((8080 + i))/health > /dev/null 2>&1; then
        echo "✅ Process $i container is healthy"
        ((healthy++))
    else
        echo "⚠️  Process $i container not ready yet"
    fi
done

if curl -s http://localhost:8090/health > /dev/null 2>&1; then
    echo "✅ Web interface is healthy"
else
    echo "⚠️  Web interface not ready yet"
fi

echo ""
echo "🎉 Docker Vector Clock Demo is running!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 Web Interface: http://localhost:8090"
echo "🐳 Container Status: $COMPOSE_CMD ps"
echo "📊 Container Logs: $COMPOSE_CMD logs -f"
echo "🛑 Stop Demo: $COMPOSE_CMD down"
echo ""
echo "📋 Direct API Access:"
for i in {0..2}; do
    echo "   Process $i: http://localhost:$((8080 + i))/status"
done
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $healthy -eq 3 ]; then
    echo "✅ All vector clock containers are healthy!"
    
    # Send initial test messages
    echo "📨 Sending initial test messages..."
    sleep 2
    
    curl -s -X POST http://localhost:8081/message \
         -H "Content-Type: application/json" \
         -d '{"senderId": 0, "vectorClock": [1,0,0], "content": "Docker init message"}' > /dev/null
    
    curl -s -X POST http://localhost:8082/message \
         -H "Content-Type: application/json" \
         -d '{"senderId": 1, "vectorClock": [1,1,0], "content": "Docker response"}' > /dev/null
    
    echo "✅ Initial messages sent. Ready for demonstration!"
else
    echo "⚠️  Some containers may still be starting up. Check logs if needed:"
    echo "   $COMPOSE_CMD logs"
fi
