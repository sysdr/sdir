# Fault Tolerance vs High Availability Demo

This demo showcases the difference between **Fault Tolerance** and **High Availability** patterns in distributed systems through a practical microservices implementation.

## Architecture

- **Frontend**: React dashboard with real-time metrics and interactive testing
- **API Gateway**: Load balancer with health checks and failure injection
- **Payment Service**: Fault tolerant with circuit breakers, retries, and graceful degradation
- **User Services**: 3 instances for high availability with automatic failover
- **Load Balancer**: Nginx for traffic distribution

## Dashboard Features

- **Real-time Metrics**: Live service health, response times, and circuit breaker states
- **Interactive Testing**: One-click verification of all system components
- **Visual Indicators**: Color-coded status indicators and circuit breaker visualization
- **Request History**: Historical charts showing success rates and response times
- **Service Monitoring**: Individual service instance health and performance tracking

## Quick Start

```bash
./demo.sh
```

Access the dashboard at http://localhost:80

## Features Demonstrated

### Fault Tolerance (Payment Service)
- **Circuit Breaker Pattern**: Prevents cascade failures
- **Exponential Backoff Retry**: Intelligent retry with jitter
- **Graceful Degradation**: Fallback responses when service is down
- **Timeout Handling**: Proper timeout management

### High Availability (User Services)
- **Load Balancing**: Round-robin distribution across instances
- **Health Checks**: Automatic unhealthy instance detection
- **Automatic Failover**: Traffic routing away from failed instances
- **Redundant Instances**: Multiple service copies for resilience

## Testing

### Automated Testing
Run comprehensive system tests:
```bash
cd tests && npm test
```

### Quick Verification
Check if all services are running properly:
```bash
./verify_demo.sh
```

### Interactive Testing

1. **Verify All**: Click the "Verify All" button for comprehensive testing
   - Tests payment service functionality
   - Verifies load balancer distribution
   - Tests fault tolerance with circuit breakers
   - Validates high availability failover
   - Checks metrics collection

2. **Test Fault Tolerance**: Click "Test Fault Tolerance" button
   - Watch circuit breaker state change
   - See retry attempts increase
   - Observe graceful degradation

3. **Test High Availability**: Click "Test High Availability" button
   - One user service instance will fail
   - Traffic continues to healthy instances
   - Load balancer maintains service availability

4. **Reset System**: Click "Reset System" to return all services to healthy state

## Cleanup

```bash
./cleanup.sh
```

## Key Insights

- **Fault Tolerance**: Handles failures within components
- **High Availability**: Uses redundancy across components  
- **Both are needed**: Modern systems require both patterns
- **Trade-offs**: Performance vs consistency, cost vs reliability

## Production Considerations

- Monitor circuit breaker states and retry counts
- Set appropriate timeout values based on SLA requirements
- Use health checks that reflect actual service capability
- Plan for graceful degradation scenarios
- Implement proper logging and observability
