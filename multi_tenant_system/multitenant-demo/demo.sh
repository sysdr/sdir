#!/bin/bash

# Multi-Tenant System Architecture Demo
# Complete implementation of all three tenancy patterns

set -e

echo "🏢 Multi-Tenant System Architecture Demo"
echo "========================================"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    echo "🔍 Checking prerequisites..."
    
    if ! command_exists docker; then
        echo "❌ Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command_exists docker-compose; then
        echo "❌ Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    echo "✅ All prerequisites met!"
    echo ""
}

# Install dependencies
install_dependencies() {
    echo "📦 Installing dependencies..."
    
    # Backend dependencies
    cd backend && npm install && cd ..
    
    # Frontend dependencies  
    cd frontend && npm install && cd ..
    
    # Test dependencies
    cd tests && npm install && cd ..
    
    echo "✅ Dependencies installed!"
    echo ""
}

# Build and start services
start_services() {
    echo "🐳 Building and starting services..."
    
    # Build and start all services
    docker-compose up --build -d
    
    echo "⏳ Waiting for services to be ready..."
    
    # Wait for databases to be ready
    echo "   Waiting for PostgreSQL (shared)..."
    timeout 60 bash -c 'until docker-compose exec -T postgres-shared pg_isready -h localhost -U admin; do sleep 2; done'
    
    echo "   Waiting for PostgreSQL (tenant1)..."
    timeout 60 bash -c 'until docker-compose exec -T postgres-tenant1 pg_isready -h localhost -U tenant1_user; do sleep 2; done'
    
    echo "   Waiting for Redis..."
    timeout 60 bash -c 'until docker-compose exec -T redis redis-cli ping; do sleep 2; done'
    
    echo "   Waiting for backend API..."
    timeout 60 bash -c 'until curl -s http://localhost:8080/health; do sleep 2; done'
    
    echo "✅ All services are ready!"
    echo ""
}

# Display access information
show_access_info() {
    echo "🌐 Access Information:"
    echo "================================"
    echo "🎯 Frontend Dashboard:  http://localhost:3000"
    echo "⚙️  Backend API:        http://localhost:8080"
    echo "📊 API Documentation:   http://localhost:8080/docs"
    echo "📈 Grafana Monitoring:  http://localhost:3001 (admin/admin123)"
    echo ""
    echo "🗄️  Database Access:"
    echo "   Shared DB:    localhost:5432 (admin/password123)"
    echo "   Tenant1 DB:   localhost:5433 (tenant1_user/tenant1_pass)"
    echo "   Redis:        localhost:6379"
    echo ""
}

# Run tests
run_tests() {
    echo "🧪 Running comprehensive tests..."
    
    # Wait a bit more for services to fully initialize
    sleep 10
    
    cd tests
    npm test
    cd ..
    
    echo "✅ All tests passed!"
    echo ""
}

# Main execution
main() {
    check_prerequisites
    install_dependencies
    start_services
    show_access_info
    
    echo "🎉 Multi-Tenant Demo is ready!"
    echo ""
    echo "📋 What to try next:"
    echo "   1. Open http://localhost:3000 to explore the dashboard"
    echo "   2. Test different tenancy patterns in the Tenant Management tab"
    echo "   3. Run isolation tests in the Isolation Testing tab"
    echo "   4. Monitor performance in the Performance Metrics tab"
    echo "   5. Run automated tests: ./test_demo.sh"
    echo ""
    echo "🛑 To stop the demo: ./cleanup.sh"
    
    # Optionally run tests
    read -p "🤔 Would you like to run the automated tests now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        run_tests
    fi
}

main
