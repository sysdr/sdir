# Distributed Cache Topology Demonstrator

A comprehensive demonstration of distributed caching patterns and failure modes.

## Quick Start

```bash
# Start the demonstration
./start_demo.sh

# Access web interface
open http://localhost:5000
```

## Features

### Cache Patterns Demonstrated
- **Cache-Aside**: Lazy loading with TTL jitter to prevent stampedes
- **Write-Through**: Synchronous cache and database updates
- **Write-Behind**: Asynchronous database writes for better performance

### Failure Simulations
- **Cache Stampede**: Multiple concurrent requests for expired data
- **Network Partition**: Redis connectivity failures
- **Performance Analysis**: Real-time metrics and latency tracking

### Testing Scenarios

1. **Basic Functionality**
   ```bash
   python tests/test_cache_patterns.py
   ```

2. **Cache-Aside Pattern**
   - Enter key "user_123" in Cache-Aside section
   - Click "Get Value" - observe cache MISS latency
   - Click again - observe cache HIT latency (faster)

3. **Write Patterns Comparison**
   - Test Write-Through: Enter key/value, observe synchronous latency
   - Test Write-Behind: Enter key/value, observe async latency (faster)

4. **Failure Scenarios**
   - Click "Cache Stampede" - watch logs for concurrent requests
   - Click "Network Partition" - observe degraded performance

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Flask App     │    │  Redis Cluster  │    │   Database      │
│  (Cache Logic)  │◄──►│   (4 DBs for    │◄──►│  (Simulated)    │
│                 │    │   different     │    │                 │
│                 │    │   patterns)     │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         ▲
         │ WebSocket
         ▼
┌─────────────────┐
│   Web UI        │
│ (Real-time      │
│  Monitoring)    │
└─────────────────┘
```

## Key Insights Demonstrated

### Performance Characteristics
- Cache-aside miss: ~55ms (includes DB query)
- Cache-aside hit: ~5ms (cache only)
- Write-through: ~105ms (synchronous DB write)
- Write-behind: ~5ms (async DB write)

### Consistency Models
- **Strong Consistency**: Write-through pattern
- **Eventual Consistency**: Write-behind pattern
- **Best Effort**: Cache-aside with TTL

### Failure Patterns
- **Stampede Prevention**: TTL jitter (30-36 seconds)
- **Graceful Degradation**: Mock clients during partitions
- **Observability**: Real-time metrics and logging

## Troubleshooting

### Port Conflicts
```bash
# If port 5000 is busy
docker-compose down
# Edit docker-compose.yml to change port mapping
# Then restart
docker-compose up -d
```

### Redis Connection Issues
```bash
# Check Redis health
docker-compose exec redis-primary redis-cli ping

# View Redis logs
docker-compose logs redis-primary
```

### Application Errors
```bash
# View application logs
docker-compose logs cache-demo

# Check container status
docker-compose ps
```

## Cleanup

```bash
# Stop all services
docker-compose down

# Remove volumes (clears Redis data)
docker-compose down -v

# Remove built images
docker-compose down --rmi all
```

## Educational Value

This demonstration provides hands-on experience with:

1. **Cache Pattern Selection**: Understanding when to use each pattern
2. **Performance Trade-offs**: Measuring latency vs consistency trade-offs
3. **Failure Handling**: Observing system behavior during outages
4. **Scalability Patterns**: TTL jitter and stampede prevention
5. **Production Readiness**: Monitoring, logging, and health checks

Perfect for system design interviews, production architecture decisions, and team education on distributed caching concepts.
