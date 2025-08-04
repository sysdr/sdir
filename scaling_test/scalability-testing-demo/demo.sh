#!/bin/bash

# Scalability Testing Demo - Service Startup
# Starts the scalability testing framework services

set -e

echo "🚀 Starting Scalability Testing Framework Demo"
echo "=============================================="

# Check if we're in the right directory
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found. Please run this script from the project root directory."
    exit 1
fi

echo "📁 Project structure verified..."

echo "🔧 Checking Python dependencies..."
if [ ! -f "requirements.txt" ]; then
    echo "❌ Error: requirements.txt not found. Please ensure all project files are present."
    exit 1
fi

echo "🧪 Checking test configuration..."
if [ ! -f "tests/locustfile.py" ]; then
    echo "❌ Error: tests/locustfile.py not found. Please ensure all project files are present."
    exit 1
fi

echo "🐳 Checking Docker configuration..."
if [ ! -f "docker-compose.yml" ]; then
    echo "❌ Error: docker-compose.yml not found. Please ensure all project files are present."
    exit 1
fi

echo "📦 Checking Dockerfile..."
if [ ! -f "Dockerfile" ]; then
    echo "❌ Error: Dockerfile not found. Please ensure all project files are present."
    exit 1
fi

echo "📊 Checking monitoring configuration..."
if [ ! -f "monitoring/prometheus.yml" ]; then
    echo "❌ Error: monitoring/prometheus.yml not found. Please ensure all project files are present."
    exit 1
fi

echo "📜 Checking test scripts..."
if [ ! -f "scripts/run_scalability_tests.py" ]; then
    echo "❌ Error: scripts/run_scalability_tests.py not found. Please ensure all project files are present."
    exit 1
fi

echo "📊 Checking analysis scripts..."
if [ ! -f "scripts/analyze_results.py" ]; then
    echo "❌ Error: scripts/analyze_results.py not found. Please ensure all project files are present."
    exit 1
fi

echo "🔧 Installing Python dependencies..."
pip install -r requirements.txt

echo "🐳 Building Docker containers..."
docker-compose build

echo "🚀 Starting services..."
docker-compose up -d

echo "⏳ Waiting for services to be ready..."
sleep 30

echo "🧪 Running scalability tests..."
python scripts/run_scalability_tests.py

echo "📊 Analyzing results..."
python scripts/analyze_results.py

echo ""
echo "✅ Demo completed successfully!"
echo ""
echo "🌐 Access points:"
echo "  📊 Main Dashboard: http://localhost:8000/dashboard"
echo "  🏥 Health Check: http://localhost:8000/health"
echo "  📈 Prometheus: http://localhost:9090"
echo "  📉 Grafana: http://localhost:3000 (admin/admin)"
echo ""
echo "🧪 To run additional tests:"
echo "  locust -f tests/locustfile.py --host http://localhost:8000"
echo ""
echo "📁 Results saved in: $(pwd)/results/"




echo ""
echo "✅ Demo completed successfully!"
echo ""
echo "🌐 Access points:"
echo "  📊 Main Dashboard: http://localhost:8000/dashboard"
echo "  🏥 Health Check: http://localhost:8000/health"
echo "  📈 Prometheus: http://localhost:9090"
echo "  📉 Grafana: http://localhost:3000 (admin/admin)"
echo ""
echo "🧪 To run additional tests:"
echo "  ./run_tests.sh"
echo "  locust -f tests/locustfile.py --host http://localhost:8000"
echo ""
echo "📁 Results saved in: $(pwd)/results/"
echo ""
echo "🎯 Next Steps:"
echo "1. Open browser to http://localhost:8000/dashboard"
echo "2. Run: ./run_tests.sh"
echo "3. Observe system behavior under different load patterns"
echo "4. Check Prometheus metrics at http://localhost:9090"
echo "5. Run ./cleanup.sh when finished"