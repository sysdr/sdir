# Circular Dependencies Demo

This demo shows how circular dependencies cause resource exhaustion in microservices.

## Architecture

- **User Service** (3001): Handles user requests
- **Order Service** (3002): Processes orders
- **Inventory Service** (3003): Checks inventory (calls back to User Service - CIRCULAR!)
- **Dashboard** (8080): Real-time monitoring

## What Happens

1. User Service receives request → calls Order Service
2. Order Service → calls Inventory Service
3. Inventory Service → calls User Service (CIRCLE!)
4. Thread pools fill up waiting for each other
5. System deadlocks under load

## Run the Demo

```bash
./demo.sh
```

Then open: http://localhost:8080

## Watch It Break

1. Click "Trigger Circular Calls"
2. Watch thread utilization hit 100%
3. See requests start failing
4. Observe circuit breaker preventing cascade

## Automated Testing

Run the automated test script to execute all demo scenarios:

```bash
cd circular-deps-demo
./test-demo.sh
```

The test script will:
- ✅ Check service health
- ✅ Make normal requests (no circular dependency)
- ✅ Enable circular dependency pattern
- ✅ Trigger low load test (5 requests)
- ✅ Trigger high load test (20 requests at 10 req/s)
- ✅ Show thread pool exhaustion
- ✅ Demonstrate circuit breaker activation
- ✅ Test system recovery

**Watch the dashboard** at http://localhost:8080 while the test runs to see:
- Thread utilization increasing
- Latency spikes in the chart
- Request counts increasing
- Circuit breaker status changes
- System recovery after disabling circular calls

## Clean Up

```bash
./cleanup.sh
```

## Learning Points

- Circular dependencies cause deadlocks
- Thread pool exhaustion happens fast (< 3 seconds at 5000 RPS)
- Request ID tracking detects circles
- Circuit breakers prevent cascading failures
- Timeouts alone don't solve the problem
