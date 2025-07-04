#!/bin/bash

echo "🚀 Starting Read-Heavy vs Write-Heavy Systems Demo (Local Mode)..."

# Check if Python is available
if ! command -v python3 &> /dev/null; then
    echo "❌ Python 3 is not installed. Please install Python 3 first."
    exit 1
fi

# Check if virtual environment exists
if [ ! -d "venv" ]; then
    echo "📦 Creating virtual environment..."
    python3 -m venv venv
fi

# Activate virtual environment
echo "🔧 Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "📥 Installing dependencies..."
pip install -r requirements.txt

# Set local environment variables
export REDIS_URL="redis://localhost:6379"
export DATABASE_URL="postgresql://demo:demo123@localhost:5432/readwrite_demo"
export FLASK_ENV="development"

# Check if Redis is available
if ! command -v redis-server &> /dev/null; then
    echo "⚠️  Redis is not installed. The demo will run with limited functionality."
    echo "   Install Redis: brew install redis (macOS) or apt-get install redis (Ubuntu)"
fi

# Check if PostgreSQL is available
if ! command -v psql &> /dev/null; then
    echo "⚠️  PostgreSQL is not installed. The demo will run with limited functionality."
    echo "   Install PostgreSQL: brew install postgresql (macOS) or apt-get install postgresql (Ubuntu)"
fi

echo "🌟 Starting Flask application..."
echo "📱 Demo will be available at: http://localhost:5000"
echo "🛑 Stop with Ctrl+C"

python app.py