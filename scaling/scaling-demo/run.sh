#!/bin/bash

echo "🚀 Starting Scaling Demo..."

# Check if running in Docker
if [ -f /.dockerenv ]; then
    echo "Running in Docker container"
    python backend/app.py
else
    echo "Running locally"
    # Install dependencies if needed
    if [ ! -d "venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv venv
        source venv/bin/activate
        pip install -r requirements.txt
    else
        source venv/bin/activate
    fi
    
    # Run the application
    python backend/app.py
fi
