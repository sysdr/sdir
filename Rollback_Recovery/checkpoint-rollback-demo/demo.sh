#!/bin/bash

set -e

echo "🚀 Starting Checkpoint and Rollback Recovery Demo..."

# Build and start services
echo "Building Docker containers..."
docker-compose build --no-cache

echo "Starting services..."
docker-compose up -d

# Wait for services to be ready
echo "Waiting for services to initialize..."
sleep 30

# Check service health
echo "Checking service health..."
docker-compose ps

# Run tests
echo "Running tests..."
docker-compose exec -T task-processor python -m pytest tests/ -v || true

# Create some demo tasks
echo "Creating demo tasks..."
curl -X POST http://localhost:8080/tasks/create \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "task_type=data_processing&steps=15&should_fail=false" || true

curl -X POST http://localhost:8080/tasks/create \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "task_type=file_conversion&steps=20&should_fail=true" || true

curl -X POST http://localhost:8080/tasks/create \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "task_type=batch_calculation&steps=10&should_fail=false" || true

# Give tasks time to process
sleep 10

# Create checkpoint
echo "Creating checkpoint..."
curl -X POST http://localhost:8080/checkpoints/create || true

echo ""
echo "✅ Demo is ready!"
echo ""
echo "🌐 Access the dashboard at: http://localhost:8080"
echo ""
echo "📊 Features to explore:"
echo "  • Monitor task processing in real-time"
echo "  • Create manual checkpoints"
echo "  • Trigger rollbacks to previous checkpoints"
echo "  • Create tasks with different failure scenarios"
echo ""
echo "🔍 To view logs:"
echo "  docker-compose logs -f task-processor"
echo "  docker-compose logs -f web-dashboard"
echo ""
echo "🧪 To run tests:"
echo "  docker-compose exec task-processor python -m pytest tests/ -v"
echo ""
