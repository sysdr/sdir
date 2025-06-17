# Distributed Locking Mechanisms Demo

This demo implements and visualizes various distributed locking mechanisms as discussed in System Design Interview Roadmap Issue #68.

## Features

- **Multiple Lock Mechanisms**: Redis, Database-based, and simulated ZooKeeper
- **Fencing Tokens**: Prevents stale operations from corrupted lock holders  
- **Failure Simulation**: Process pause, network partition, TTL expiration
- **Real-time Dashboard**: Live visualization of lock states and events
- **Comprehensive Testing**: Unit tests for all locking scenarios

## Quick Start

1. **Run the Demo**:
   ```bash
   ./run_demo.sh
   ```

2. **Open Dashboard**: Navigate to http://localhost:8080

3. **Run Tests**:
   ```bash
   ./test_demo.sh
   ```

## Demo Scenarios

### 1. Normal Operation
- Lock acquisition and release
- Protected resource access
- Proper cleanup

### 2. Lock Contention  
- Multiple clients competing for same resource
- First-come-first-served semantics
- Queue-based waiting

### 3. Process Pause Simulation
- Client holds lock then pauses (GC/network)
- TTL expiration allows new client
- Stale client rejected by fencing tokens

### 4. Mechanism Comparison
- Performance characteristics
- Consistency guarantees  
- Failure behavior

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Client A      │    │   Lock Service  │    │ Protected       │
│                 │    │                 │    │ Resource        │
│ ┌─────────────┐ │    │ ┌─────────────┐ │    │ ┌─────────────┐ │
│ │Lock Manager │ │◄──►│ │Redis/DB/ZK  │ │    │ │Fencing      │ │
│ └─────────────┘ │    │ └─────────────┘ │    │ │Validation   │ │
│                 │    │                 │    │ └─────────────┘ │
└─────────────────┘    └─────────────────┘    └─────────────────┘
                                                       ▲
┌─────────────────┐                                   │
│   Client B      │                                   │
│                 │                                   │
│ ┌─────────────┐ │───────────────────────────────────┘
│ │Lock Manager │ │
│ └─────────────┘ │
│                 │
└─────────────────┘
```

## Key Insights Demonstrated

1. **Temporal Violations**: How process pauses can break mutual exclusion
2. **Fencing Tokens**: Monotonic ordering prevents stale operations  
3. **Consistency Trade-offs**: Different mechanisms offer different guarantees
4. **Failure Recovery**: Circuit breakers and health-based release

## Files Structure

```
distributed-locks-demo/
├── src/
│   ├── lock_mechanisms.py    # Core locking implementations
│   └── web_dashboard.py      # Flask web interface
├── tests/
│   └── test_locks.py         # Comprehensive test suite
├── templates/
│   └── dashboard.html        # Web dashboard UI
├── docker-compose.yml        # Service orchestration
├── Dockerfile               # Container definition
├── requirements.txt         # Python dependencies
├── run_demo.sh             # Main demo launcher
└── test_demo.sh            # Test runner
```

## Advanced Usage

### Custom Lock Configuration

```python
config = LockConfig(
    ttl_seconds=30,      # Lock timeout
    retry_attempts=3,    # Acquisition retries  
    backoff_base=0.1,    # Backoff timing
    fencing_enabled=True # Token validation
)
```

### Adding New Mechanisms

Implement the `DistributedLock` interface:

```python
class CustomLock(DistributedLock):
    async def acquire(self, resource_id, client_id, config):
        # Implementation
        pass
        
    async def release(self, resource_id, client_id, token):
        # Implementation  
        pass
```

## Troubleshooting

- **Services won't start**: Check Docker daemon and port availability
- **Redis connection failed**: Verify Redis container is healthy
- **Tests failing**: Ensure all services are running before testing
- **Dashboard not loading**: Check that port 8080 is available

## Production Considerations

This demo is for educational purposes. Production usage requires:

- Proper monitoring and alerting
- Circuit breaker implementations  
- Multi-region coordination strategies
- Comprehensive failure recovery
- Performance optimization based on workload
