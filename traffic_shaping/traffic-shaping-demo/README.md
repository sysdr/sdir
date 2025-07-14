# Traffic Shaping and Rate Limiting Demo

A comprehensive demonstration of production-grade rate limiting algorithms and traffic shaping techniques.

## Features

- **Multiple Rate Limiting Algorithms**
  - Token Bucket: Allows bursts, memory efficient
  - Sliding Window: Precise limiting, higher memory usage
  - Fixed Window: Simple implementation, boundary effects

- **Distributed Coordination**
  - Redis-based shared state
  - Atomic operations using Lua scripts
  - Connection pooling and optimization

- **Real-time Monitoring**
  - Live metrics and statistics
  - Interactive charts and visualizations
  - Request logs and debugging

- **Load Testing Suite**
  - Burst testing capabilities
  - Sustained load testing
  - Comparative analysis

## Quick Start

1. **Setup and run the demo:**
   ```bash
   ./demo.sh
   ```

2. **Access the web dashboard:**
   - Open http://localhost:8000 in your browser
   - Test different rate limiting algorithms
   - Monitor real-time metrics

3. **API Testing:**
   ```bash
   # Test token bucket
   curl -X POST http://localhost:8000/api/request/token_bucket

   # Test sliding window
   curl -X POST http://localhost:8000/api/request/sliding_window

   # Test fixed window
   curl -X POST http://localhost:8000/api/request/fixed_window
   ```

4. **Cleanup:**
   ```bash
   ./cleanup.sh
   ```

## Architecture

### Rate Limiting Algorithms

1. **Token Bucket**
   - Capacity: 10 tokens
   - Refill rate: 2 tokens/second
   - Allows burst traffic up to capacity

2. **Sliding Window**
   - Window size: 60 seconds
   - Max requests: 100 per window
   - Precise request counting

3. **Fixed Window**
   - Window size: 60 seconds
   - Max requests: 50 per window
   - Simple implementation

### Components

- **FastAPI Application**: Main web service with async support
- **Redis**: Distributed state storage and coordination
- **Web Dashboard**: Real-time monitoring and testing interface
- **Load Tester**: Comprehensive testing suite

## Testing Scenarios

### Manual Testing
1. Use the web dashboard to send individual requests
2. Compare algorithm behaviors under different load patterns
3. Monitor real-time metrics and response times

### Automated Testing
```bash
# Run load tests
docker-compose run --rm load-tester

# Custom testing
python tests/load_test.py
```

### Bulk Testing
1. Select algorithm type
2. Configure request count and interval
3. Monitor progress and results in real-time

## Key Insights

### Token Bucket
- **Best for**: Bursty traffic patterns
- **Advantages**: Allows legitimate bursts, memory efficient
- **Trade-offs**: May allow sustained bursts that overwhelm downstream

### Sliding Window
- **Best for**: Precise rate limiting
- **Advantages**: Smooth traffic distribution, accurate limiting
- **Trade-offs**: Higher memory usage, more complex implementation

### Fixed Window
- **Best for**: Simple rate limiting needs
- **Advantages**: Easy to implement and understand
- **Trade-offs**: Boundary effects can allow 2x rate at window transitions

## Production Considerations

1. **Redis Configuration**
   - Use Redis Cluster for high availability
   - Configure appropriate memory limits
   - Monitor Redis performance metrics

2. **Algorithm Selection**
   - Choose based on traffic patterns
   - Consider memory and CPU constraints
   - Test under realistic load conditions

3. **Monitoring**
   - Track false positive/negative rates
   - Monitor processing latencies
   - Set up alerting for rate limit violations

4. **Graceful Degradation**
   - Implement fallback mechanisms
   - Fail open vs fail closed strategies
   - Circuit breaker integration

## Troubleshooting

### Common Issues

1. **Port conflicts**
   - Check if ports 8000, 6379 are available
   - Modify docker-compose.yml if needed

2. **Redis connection issues**
   - Verify Redis container is running
   - Check network connectivity

3. **Performance issues**
   - Monitor Docker resource usage
   - Adjust rate limiting parameters

### Debug Commands

```bash
# Check container status
docker-compose ps

# View logs
docker-compose logs rate-limiter-app
docker-compose logs redis

# Test Redis connectivity
docker-compose exec redis redis-cli ping
```

## License

This demo is part of the System Design Interview Roadmap series and is provided for educational purposes.
