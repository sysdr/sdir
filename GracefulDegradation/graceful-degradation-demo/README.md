# Graceful Degradation vs Fail Fast Demo

A comprehensive demonstration of graceful degradation and fail-fast patterns in Node.js applications, featuring circuit breakers, fallback strategies, and monitoring.

## 🚀 Features

- **Graceful Degradation**: Automatic fallback to cached/static data when services fail
- **Fail Fast Pattern**: Immediate failure for invalid inputs to prevent data corruption
- **Circuit Breaker**: Prevents cascading failures using the opossum library
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **Redis Integration**: Caching layer with graceful fallback
- **Docker Support**: Containerized deployment with docker-compose

## 🏗️ Architecture

The demo showcases two different approaches:

1. **Recommendations API** (`/api/recommendations/:userId`)
   - Primary: ML-based recommendations
   - Fallback 1: Redis cache
   - Fallback 2: Static trending items
   - Graceful degradation with circuit breaker

2. **Payment API** (`/api/payment`)
   - Fail-fast validation
   - Immediate rejection of invalid inputs
   - Service health checks before processing

## 📦 Prerequisites

- Node.js 18+
- Docker and Docker Compose
- Redis (included in docker-compose)

## 🛠️ Installation

1. Clone the repository:
```bash
git clone <repository-url>
cd graceful-degradation-demo
```

2. Install dependencies:
```bash
npm install
```

3. Start the application:
```bash
# Using Docker Compose (recommended)
docker-compose up -d

# Or locally
npm start
```

## 🧪 Testing

Run the test suite:
```bash
npm test
```

The tests demonstrate:
- Health endpoint functionality
- Graceful degradation behavior
- Fail-fast validation
- Circuit breaker status

## 📊 Monitoring

- **Application Metrics**: http://localhost:3000/metrics
- **Prometheus**: http://localhost:9090
- **Grafana Dashboard**: http://localhost:3001 (admin/admin)

## 🔧 Configuration

### Environment Variables
- `PORT`: Application port (default: 3000)
- `REDIS_URL`: Redis connection string (default: redis://redis:6379)
- `NODE_ENV`: Environment mode (default: development)

### Service States
Control service health via admin endpoints:
```bash
# Toggle service health
POST /admin/service/:service/toggle

# Set service latency
POST /admin/service/:service/latency
Body: {"latency": 100}
```

## 🐳 Docker

Build and run with Docker:
```bash
# Build image
docker build -t graceful-degradation-demo .

# Run container
docker run -p 3000:3000 graceful-degradation-demo
```

## 📈 Metrics

The application exposes Prometheus metrics:
- HTTP request duration
- Circuit breaker state
- Fallback activation counts
- Service health status

## 🔍 API Endpoints

- `GET /` - Main dashboard
- `GET /health` - System health status
- `GET /api/recommendations/:userId` - Product recommendations
- `POST /api/payment` - Payment processing
- `GET /metrics` - Prometheus metrics
- `GET /circuit-breaker/status` - Circuit breaker status

## 🧠 Learning Objectives

This demo helps understand:
- When to use graceful degradation vs fail-fast
- Circuit breaker pattern implementation
- Fallback strategy design
- Monitoring and observability
- Error handling best practices

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License.

