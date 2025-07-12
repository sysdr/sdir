#!/bin/bash

echo "🚀 Starting Scale Cube Demo..."

# Function to check if a port is in use
check_port() {
    local port=$1
    if lsof -i :$port >/dev/null 2>&1; then
        return 0  # Port is in use
    else
        return 1  # Port is free
    fi
}

# Function to wait for service to be ready
wait_for_service() {
    local url=$1
    local service_name=$2
    local max_attempts=30
    local attempt=1
    
    echo "⏳ Waiting for $service_name to be ready..."
    while [ $attempt -le $max_attempts ]; do
        if curl -s -o /dev/null -w "%{http_code}" "$url" | grep -q "200\|404"; then
            echo "✅ $service_name is ready!"
            return 0
        fi
        echo "   Attempt $attempt/$max_attempts - waiting..."
        sleep 2
        ((attempt++))
    done
    echo "❌ $service_name failed to start after $max_attempts attempts"
    return 1
}

# Check if port 80 is in use
if check_port 80; then
    echo "⚠️  Port 80 is in use. Load balancer will not start, but demo will continue."
    export SKIP_LOAD_BALANCER=true
fi

# Build and start all services
echo "🏗️ Building Docker images..."
docker-compose build

echo "🔥 Starting infrastructure services..."
docker-compose up -d redis user_db_1 user_db_2 product_db order_db

echo "⏳ Waiting for databases to be ready..."
sleep 15

echo "🚀 Starting application services..."
docker-compose up -d user_service_1 user_service_2 product_service order_service

echo "⏳ Waiting for application services to be ready..."
sleep 10

# Restart services if they failed due to database timing issues
echo "🔄 Restarting services to ensure database connections..."
docker-compose restart user_service_1 user_service_2 product_service order_service

echo "🌐 Starting gateways..."
docker-compose up -d gateway_1 gateway_2

echo "⏳ Waiting for gateways to be ready..."
sleep 5

# Start load balancer if port 80 is available
if [ "$SKIP_LOAD_BALANCER" != "true" ]; then
    echo "🔀 Starting load balancer..."
    docker-compose up -d load_balancer
    
    # Wait for load balancer and start web UI
    sleep 5
    echo "🎨 Starting web UI..."
    docker-compose up -d web_ui
    
    # Wait for web UI
    if wait_for_service "http://localhost:3000" "Web UI"; then
        WEB_UI_URL="http://localhost:3000"
        GATEWAY_URL="http://localhost/api/scaling-info"
    else
        echo "❌ Web UI failed to start via load balancer. Starting direct connection..."
        SKIP_LOAD_BALANCER=true
    fi
fi

# Fallback: Start web UI directly connected to gateway if load balancer failed
if [ "$SKIP_LOAD_BALANCER" = "true" ]; then
    echo "🎨 Starting web UI with direct gateway connection..."
    
    # Stop and remove any existing web UI container
    docker stop scale-cube-web-ui 2>/dev/null || true
    docker rm scale-cube-web-ui 2>/dev/null || true
    
    # Start web UI directly connected to gateway
    docker run -d -p 3000:3000 --name scale-cube-web-ui \
        --network scale-cube-demo_default \
        -e GATEWAY_URL=http://gateway_1:8000 \
        scale-cube-demo-web_ui python web/main.py
    
    if wait_for_service "http://localhost:3000" "Web UI (direct)"; then
        WEB_UI_URL="http://localhost:3000"
        GATEWAY_URL="http://localhost:3000/api/scaling-info"
    else
        echo "❌ Web UI failed to start"
        WEB_UI_URL="❌ Failed to start"
        GATEWAY_URL="❌ Failed to start"
    fi
fi

# Final health check
echo "🏥 Checking service health..."
docker-compose ps

echo ""
echo "🎉 Scale Cube Demo Setup Complete!"
echo ""
echo "🌐 Access the demo at:"
echo "   Dashboard: $WEB_UI_URL"
echo "   API Gateway: $GATEWAY_URL"
echo ""

# Verify services are actually working
echo "🧪 Verifying services..."
if curl -s "$GATEWAY_URL" >/dev/null 2>&1; then
    echo "✅ API Gateway is responding"
else
    echo "⚠️  API Gateway may not be fully ready yet"
fi

if curl -s "$WEB_UI_URL" >/dev/null 2>&1; then
    echo "✅ Web UI is responding"
else
    echo "⚠️  Web UI may not be fully ready yet"
fi

echo ""
echo "🧪 Test the scaling:"
echo "   1. Visit $WEB_UI_URL"
echo "   2. Go to 'Test Scaling in Action'"
echo "   3. Try the X, Y, and Z-axis tests"
echo ""
echo "🔍 Monitor with:"
echo "   docker-compose logs -f"
echo ""
echo "🛑 Stop with:"
echo "   ./cleanup.sh"
echo ""

# Show any failed services
echo "⚠️  Failed services (if any):"
docker-compose ps | grep -E "Exit|Restarting" || echo "   None - all services are running!"

echo ""
echo "📋 Quick Status:"
echo "   - Redis: $(docker-compose ps -q redis >/dev/null && echo "✅" || echo "❌")"
echo "   - Databases: $(docker-compose ps -q user_db_1 user_db_2 product_db order_db | wc -l | tr -d ' ')/4 running"
echo "   - App Services: $(docker-compose ps -q user_service_1 user_service_2 product_service order_service | wc -l | tr -d ' ')/4 running"
echo "   - Gateways: $(docker-compose ps -q gateway_1 gateway_2 | wc -l | tr -d ' ')/2 running"
echo "   - Load Balancer: $(docker-compose ps -q load_balancer >/dev/null && echo "✅" || echo "❌ (port 80 conflict)")"
echo "   - Web UI: $(curl -s -o /dev/null -w "%{http_code}" "$WEB_UI_URL" 2>/dev/null | grep -q "200" && echo "✅" || echo "❌")"
