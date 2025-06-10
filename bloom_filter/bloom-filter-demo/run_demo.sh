#!/bin/bash

# Bloom Filter Demo Startup Script with Enhanced Debugging

set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}=== Starting Bloom Filter Demo ===${NC}"

# Function to check if port is available
check_port() {
    if lsof -Pi :$1 -sTCP:LISTEN -t >/dev/null 2>&1; then
        echo -e "${YELLOW}Port $1 is already in use. Attempting to free it...${NC}"
        # Try to kill processes using the port
        lsof -ti:$1 | xargs kill -9 >/dev/null 2>&1 || true
        sleep 2
    fi
}

# Function to debug directory structure
debug_structure() {
    echo -e "${BLUE}=== Debugging Directory Structure ===${NC}"
    echo "Current directory: $(pwd)"
    echo "Directory contents:"
    ls -la
    echo ""
    echo "Templates directory:"
    if [ -d "templates" ]; then
        ls -la templates/
    else
        echo -e "${RED}Templates directory not found!${NC}"
    fi
    echo ""
    echo "Source directory:"
    if [ -d "src" ]; then
        ls -la src/
    else
        echo -e "${RED}Source directory not found!${NC}"
    fi
}

# Function to fix common issues
fix_common_issues() {
    echo -e "${YELLOW}=== Checking and fixing common issues ===${NC}"
    
    # Ensure templates directory exists with correct file
    if [ ! -d "templates" ]; then
        echo -e "${RED}Templates directory missing, creating it...${NC}"
        mkdir -p templates
    fi
    
    if [ ! -f "templates/index.html" ]; then
        echo -e "${RED}index.html missing, recreating it...${NC}"
        # Create a minimal HTML file as fallback
        cat > templates/index.html << 'HTML_EOF'
<!DOCTYPE html>
<html><head><title>Bloom Filter Demo</title></head>
<body><h1>Bloom Filter Demo</h1><p>Demo is starting up...</p></body></html>
HTML_EOF
    fi
    
    # Ensure src directory exists
    if [ ! -d "src" ]; then
        echo -e "${RED}Source directory missing!${NC}"
        echo "Please run the setup script again."
        exit 1
    fi
}

# Check if required ports are available
check_port 8080
check_port 6379

# Debug current structure
debug_structure

# Fix common issues
fix_common_issues

echo -e "${GREEN}[1/6] Building and starting services with Docker Compose...${NC}"
docker-compose down -v >/dev/null 2>&1 || true  # Clean start
docker-compose up --build -d

echo -e "${GREEN}[2/6] Waiting for services to be ready...${NC}"
sleep 15

# Enhanced health check with debugging
echo -e "${GREEN}[3/6] Running health checks with debugging...${NC}"
for i in {1..30}; do
    if curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Application is healthy!${NC}"
        break
    fi
    echo "Waiting for application to start... ($i/30)"
    
    # Show container logs if failing
    if [ $i -eq 10 ] || [ $i -eq 20 ]; then
        echo -e "${YELLOW}=== Container Status ===${NC}"
        docker-compose ps
        echo -e "${YELLOW}=== Application Logs ===${NC}"
        docker-compose logs app | tail -20
    fi
    
    sleep 2
    if [ $i -eq 30 ]; then
        echo -e "${RED}❌ Application failed to start properly${NC}"
        echo -e "${YELLOW}=== Final Debug Information ===${NC}"
        echo "Container status:"
        docker-compose ps
        echo ""
        echo "Application logs:"
        docker-compose logs app
        echo ""
        echo "Redis logs:"
        docker-compose logs redis
        echo -e "${YELLOW}You can still try accessing the demo at http://localhost:8080${NC}"
    fi
done

echo -e "${GREEN}[4/6] Testing API endpoints...${NC}"
# Test basic API endpoints
if curl -s http://localhost:8080/api/statistics > /dev/null 2>&1; then
    echo -e "${GREEN}✅ API endpoints are responding${NC}"
else
    echo -e "${YELLOW}⚠️  API endpoints may not be fully ready${NC}"
fi

echo -e "${GREEN}[5/6] Running automated tests...${NC}"
docker-compose exec -T app python -m pytest tests/ -v || echo -e "${YELLOW}Some tests failed, but demo will continue...${NC}"

echo -e "${GREEN}[6/6] Demo is ready!${NC}"
echo ""
echo -e "${BLUE}=== Demo URLs ===${NC}"
echo -e "🌐 Web Interface: ${GREEN}http://localhost:8080${NC}"
echo -e "🔍 Health Check: ${GREEN}http://localhost:8080/health${NC}"
echo -e "📊 API Statistics: ${GREEN}http://localhost:8080/api/statistics${NC}"
echo ""
echo -e "${BLUE}=== Demo Features ===${NC}"
echo "✅ Interactive Bloom filter operations"
echo "✅ False positive rate analysis"
echo "✅ Performance testing"
echo "✅ Distributed architecture simulation"
echo "✅ Real-time statistics"
echo ""
echo -e "${BLUE}=== Useful Commands ===${NC}"
echo "📊 View logs: docker-compose logs -f"
echo "🔧 Stop demo: docker-compose down"
echo "🧹 Clean up: docker-compose down -v"
echo "🐛 Debug structure: docker-compose exec app ls -la /app/"
echo "🔍 Check templates: docker-compose exec app ls -la /app/templates/"
echo ""
echo -e "${GREEN}🎉 Open your browser to http://localhost:8080 to start exploring!${NC}"

# Final check
echo -e "${BLUE}=== Final Verification ===${NC}"
if curl -s http://localhost:8080 > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Demo is accessible and ready for use!${NC}"
else
    echo -e "${RED}❌ Demo may have issues. Check the troubleshooting section below.${NC}"
    echo ""
    echo -e "${YELLOW}=== Troubleshooting Steps ===${NC}"
    echo "1. Check container status: docker-compose ps"
    echo "2. View application logs: docker-compose logs app"
    echo "3. Restart services: docker-compose restart"
    echo "4. Rebuild from scratch: docker-compose down -v && docker-compose up --build"
    echo "5. Check file structure: docker-compose exec app find /app -name '*.html'"
fi
