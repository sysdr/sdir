#!/bin/bash

echo "🚀 Starting Runbook Management System Demo..."

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker first."
    exit 1
fi

# Install Node.js dependencies for testing
if command -v node >/dev/null 2>&1; then
    echo "📦 Installing test dependencies..."
    npm install axios --prefix tests/
fi

echo "🔧 Building and starting services..."
docker-compose up --build -d

echo "⏳ Waiting for services to be ready..."
sleep 10

# Wait for backend to be ready
echo "🔍 Checking backend health..."
for i in {1..30}; do
    if curl -s http://localhost:3001/api/runbooks > /dev/null; then
        echo "✅ Backend is ready!"
        break
    fi
    echo "⏳ Waiting for backend... ($i/30)"
    sleep 2
done

# Wait for frontend to be ready
echo "🔍 Checking frontend health..."
for i in {1..30}; do
    if curl -s http://localhost:3000 > /dev/null; then
        echo "✅ Frontend is ready!"
        break
    fi
    echo "⏳ Waiting for frontend... ($i/30)"
    sleep 2
done

# Run tests
if [ -f "tests/test_runbooks.js" ] && command -v node >/dev/null 2>&1; then
    echo "🧪 Running API tests..."
    cd tests && node test_runbooks.js
    cd ..
fi

echo ""
echo "🎉 Runbook Management System is ready!"
echo ""
echo "📋 Access Points:"
echo "   🌐 Web Interface: http://localhost:3000"
echo "   🔧 Backend API: http://localhost:3001/api"
echo ""
echo "🎯 Demo Features:"
echo "   1. Browse existing runbooks and their procedures"
echo "   2. Execute runbooks with real-time step tracking"
echo "   3. Create custom runbooks using the interactive editor"
echo "   4. View analytics and usage patterns"
echo "   5. Explore templates for standardized procedures"
echo ""
echo "📊 Sample Data Includes:"
echo "   - Database Connection Recovery runbook"
echo "   - API Gateway Timeout Resolution runbook"
echo "   - Service Recovery template"
echo ""
echo "🛠️ Next Steps:"
echo "   1. Open http://localhost:3000 in your browser"
echo "   2. Explore the dashboard and existing runbooks"
echo "   3. Try executing a runbook to see real-time tracking"
echo "   4. Create your own runbook using the template system"
echo ""
echo "🧹 To stop and clean up: ./cleanup.sh"
