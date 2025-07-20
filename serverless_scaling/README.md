# Serverless Scaling Demo

A comprehensive demonstration of serverless scaling patterns and auto-scaling capabilities for system design interviews.

## 🎯 Overview

This demo showcases a serverless architecture with automatic scaling capabilities, including:

- **API Gateway** - Request routing and load balancing
- **Worker Services** - Auto-scaling task processors
- **Redis** - Caching and job queue management
- **PostgreSQL** - Persistent data storage
- **Nginx** - Load balancer with rate limiting
- **Monitoring Dashboard** - Real-time metrics and scaling insights

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │    │   API Gateway   │    │  Worker Service │
│     (Nginx)     │───▶│   (FastAPI)     │───▶│   (FastAPI)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Monitoring    │    │      Redis      │    │   PostgreSQL    │
│   Dashboard     │    │   (Cache/Queue) │    │   (Database)    │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- curl (for testing)

### Start the Demo

```bash
# Start all services
./demo.sh

# Or manually
docker-compose up -d
```

### Access the Services

- **Monitoring Dashboard**: http://localhost:8080
- **API Gateway**: http://localhost:8000
- **Load Balancer**: http://localhost
- **Worker Service**: http://localhost:8001

## 🧪 Testing the System

### 1. Health Check

```bash
curl http://localhost/api/status
```

### 2. Create Tasks

```bash
# Create a simple task
curl -X POST http://localhost/api/task \
  -H 'Content-Type: application/json' \
  -d '{"type": "test", "data": {"message": "Hello World"}}'

# Create multiple tasks to test scaling
for i in {1..10}; do
  curl -X POST http://localhost/api/task \
    -H 'Content-Type: application/json' \
    -d "{\"type\": \"batch_$i\", \"data\": {\"message\": \"Task $i\"}}"
done
```

### 3. Monitor Performance

```bash
# Get system metrics
curl http://localhost/api/metrics

# Check worker status
curl http://localhost:8001/worker/status
```

### 4. Load Testing

```bash
# Run load test with 20 concurrent users for 2 minutes
docker-compose --profile load-test up load-test \
  -e CONCURRENT_USERS=20 \
  -e DURATION=120
```

## 🔄 Scaling the System

### Manual Scaling

```bash
# Scale up to 3 workers
docker-compose up -d --scale worker-service=3

# Scale down to 1 worker
docker-compose up -d --scale worker-service=1
```

### Auto-Scaling Logic

The system includes built-in scaling recommendations based on:

- Queue length vs. active workers
- Processing time trends
- Error rates
- System load

## 📊 Monitoring Features

The monitoring dashboard provides:

- **Real-time Metrics**: Request count, active workers, queue length
- **Performance Stats**: Tasks per minute, average processing time
- **Worker Status**: Active workers with last seen timestamps
- **Task Queue**: Recent tasks with status and worker assignment
- **Scaling Recommendations**: Automatic suggestions for scaling actions

## 🏗️ System Design Concepts Demonstrated

### 1. **Load Balancing**
- Nginx distributes requests across multiple API gateway instances
- Round-robin load balancing with health checks

### 2. **Queue-Based Architecture**
- Redis acts as a job queue for task processing
- Workers pull tasks from the queue (pull vs push model)

### 3. **Auto-Scaling**
- Workers can be scaled up/down based on queue length
- Horizontal scaling with stateless worker instances

### 4. **Caching Strategy**
- Redis caches frequently accessed data
- Reduces database load and improves response times

### 5. **Monitoring and Observability**
- Real-time metrics collection
- Performance monitoring and alerting
- Scaling decision automation

### 6. **Fault Tolerance**
- Multiple worker instances for redundancy
- Graceful degradation under load
- Health checks and automatic failover

## 🔧 Configuration

### Environment Variables

```bash
# API Gateway
REDIS_URL=redis://redis:6379
WORKER_SERVICE_URL=http://worker-service:8001

# Worker Service
REDIS_URL=redis://redis:6379
DATABASE_URL=postgresql://user:password@postgres:5432/serverless_demo

# Load Testing
TARGET_URL=http://nginx
CONCURRENT_USERS=10
DURATION=60
```

### Docker Compose Services

- **api-gateway**: FastAPI service for request routing
- **worker-service**: Auto-scaling task processors
- **nginx**: Load balancer with rate limiting
- **redis**: Caching and job queue
- **postgres**: Persistent database
- **monitoring**: Real-time metrics dashboard
- **load-test**: Load testing service (optional)

## 🧹 Cleanup

```bash
# Stop all services
docker-compose down

# Clean up everything (including volumes)
./setup.sh
```

## 📚 Learning Resources

This demo is part of the **System Design Interview Roadmap** and demonstrates:

- Serverless architecture patterns
- Auto-scaling strategies
- Queue-based processing
- Load balancing techniques
- Monitoring and observability
- Performance optimization

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

This project is part of the System Design Interview Roadmap educational content. 