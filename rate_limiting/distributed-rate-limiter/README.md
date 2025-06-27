# Distributed Rate Limiter

A production-ready distributed rate limiting system implemented in Python with Flask and Redis. This project demonstrates three different rate limiting algorithms: Token Bucket, Sliding Window, and Fixed Window.

## Features

- **Multiple Rate Limiting Algorithms**:
  - Token Bucket Algorithm
  - Sliding Window Algorithm
  - Fixed Window Algorithm
- **Redis Backend**: Distributed rate limiting with Redis
- **Fallback Support**: Local storage fallback when Redis is unavailable
- **RESTful API**: Easy-to-use HTTP endpoints
- **Web Dashboard**: Visual interface for testing and monitoring
- **Comprehensive Testing**: Unit tests and performance tests
- **Docker Support**: Easy deployment with Docker and Docker Compose

## Prerequisites

Before running the demo, ensure you have the following installed:

- **Docker** (version 20.10 or higher)
- **Docker Compose** (version 2.0 or higher)
- **Python** (version 3.8 or higher)
- **curl** (for API testing)

### Installing Prerequisites

#### macOS
```bash
# Install Docker Desktop
brew install --cask docker

# Install Python (if not already installed)
brew install python

# Install curl (if not already installed)
brew install curl
```

#### Ubuntu/Debian
```bash
# Install Docker
sudo apt update
sudo apt install docker.io docker-compose

# Install Python
sudo apt install python3 python3-pip

# Install curl
sudo apt install curl
```

#### Windows
- Download and install [Docker Desktop](https://www.docker.com/products/docker-desktop)
- Download and install [Python](https://www.python.org/downloads/)
- curl is typically included with Windows 10/11

## Quick Start

### Option 1: Using the Demo Script (Recommended)

1. **Run the demo script**:
   ```bash
   ./demo.sh
   ```

   This script will:
   - Check all prerequisites
   - Build the Docker image
   - Start all services (Flask app + Redis)
   - Run comprehensive tests
   - Display service URLs and status

2. **Access the application**:
   - Web UI: http://localhost:5000
   - API endpoints: http://localhost:5000/api/*

3. **Clean up when done**:
   ```bash
   ./cleanup.sh
   ```

### Option 2: Manual Setup

1. **Build and start services**:
   ```bash
   docker-compose up --build -d
   ```

2. **Check service status**:
   ```bash
   docker-compose ps
   ```

3. **View logs**:
   ```bash
   docker-compose logs -f
   ```

4. **Stop services**:
   ```bash
   docker-compose down
   ```

## API Endpoints

### Rate Limiting Endpoints

#### Token Bucket Algorithm
```bash
curl http://localhost:5000/api/token-bucket
```

#### Sliding Window Algorithm
```bash
curl http://localhost:5000/api/sliding-window
```

#### Fixed Window Algorithm
```bash
curl http://localhost:5000/api/fixed-window
```

### Monitoring Endpoints

#### Get Statistics
```bash
curl http://localhost:5000/api/stats
```

#### Load Testing
```bash
curl http://localhost:5000/api/load-test
```

### Using Custom Client IDs

You can specify a custom client ID using the `X-Client-ID` header:

```bash
curl -H "X-Client-ID: my-client-123" http://localhost:5000/api/token-bucket
```

## Rate Limiting Algorithms

### 1. Token Bucket Algorithm
- **Capacity**: 50 tokens
- **Refill Rate**: 5 tokens per second
- **Use Case**: Smooth traffic shaping with burst allowance

### 2. Sliding Window Algorithm
- **Window Size**: 60 seconds
- **Max Requests**: 100 requests per window
- **Use Case**: Precise rate limiting with smooth boundaries

### 3. Fixed Window Algorithm
- **Window Size**: 60 seconds
- **Max Requests**: 100 requests per window
- **Use Case**: Simple, predictable rate limiting

## Testing

### Running Tests

The demo script automatically runs tests, but you can also run them manually:

```bash
# Unit tests
python -m pytest tests/test_rate_limiters.py -v

# Performance tests
python tests/performance_test.py
```

### Manual API Testing

Test rate limiting behavior:

```bash
# Test token bucket (should allow first 50 requests, then rate limit)
for i in {1..60}; do
  curl -s http://localhost:5000/api/token-bucket | jq '.allowed'
  sleep 0.1
done
```

## Configuration

### Environment Variables

You can customize the application behavior by setting environment variables:

```bash
# In docker-compose.yml
environment:
  - FLASK_ENV=development
  - REDIS_HOST=redis
  - REDIS_PORT=6379
```

### Rate Limiter Configuration

Modify the rate limiter parameters in `app/main.py`:

```python
# Token Bucket
token_bucket = TokenBucketRateLimiter(redis_client, capacity=50, refill_rate=5)

# Sliding Window
sliding_window = SlidingWindowRateLimiter(redis_client, window_size=60, max_requests=100)

# Fixed Window
fixed_window = FixedWindowRateLimiter(redis_client, window_size=60, max_requests=100)
```

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web Browser   │    │   API Client    │    │   Load Tester   │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
                    ┌─────────────▼─────────────┐
                    │     Flask Application     │
                    │   (Port 5000)            │
                    └─────────────┬─────────────┘
                                  │
                    ┌─────────────▼─────────────┐
                    │        Redis              │
                    │   (Port 6379)            │
                    └───────────────────────────┘
```

## Troubleshooting

### Common Issues

1. **Port already in use**:
   ```bash
   # Check what's using the port
   lsof -i :5000
   lsof -i :6379
   
   # Kill the process or use different ports
   ```

2. **Docker permission issues**:
   ```bash
   # Add user to docker group (Linux)
   sudo usermod -aG docker $USER
   # Then log out and back in
   ```

3. **Redis connection issues**:
   ```bash
   # Check Redis logs
   docker-compose logs redis
   
   # Restart Redis
   docker-compose restart redis
   ```

4. **Application not starting**:
   ```bash
   # Check application logs
   docker-compose logs app
   
   # Rebuild the image
   docker-compose build --no-cache
   ```

### Debug Mode

To run in debug mode with more verbose output:

```bash
# Set debug environment
export FLASK_ENV=development
export FLASK_DEBUG=1

# Run with debug logging
docker-compose up --build
```

## Performance Considerations

- **Redis Persistence**: Redis is configured with AOF (Append-Only File) for data persistence
- **Connection Pooling**: The application uses Redis connection pooling for better performance
- **Lua Scripts**: Rate limiting logic uses Redis Lua scripts for atomic operations
- **Fallback Mode**: Local storage fallback ensures service availability during Redis outages

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
1. Check the troubleshooting section above
2. Review the logs: `docker-compose logs`
3. Open an issue on GitHub with detailed error information 