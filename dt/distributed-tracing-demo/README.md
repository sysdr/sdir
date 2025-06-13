# Distributed Tracing Demo

This demo showcases distributed tracing across multiple microservices using OpenTelemetry and Jaeger.

## Architecture

- **API Gateway**: Entry point for all requests
- **Order Service**: Orchestrates order processing
- **Payment Service**: Handles payment processing
- **Inventory Service**: Manages product inventory
- **Notification Service**: Sends order confirmations
- **Redis**: Inter-service communication and caching
- **Jaeger**: Distributed tracing backend

## Quick Start

1. **Build and start all services:**
   ```bash
   docker-compose up --build
   ```

2. **Wait for services to be ready (about 2-3 minutes):**
   ```bash
   # Check if all services are healthy
   docker-compose ps
   ```

3. **Run the test suite:**
   ```bash
   python3 tests/test_distributed_tracing.py
   ```

4. **Open the web interfaces:**
   - Demo Web Interface: http://localhost:3000
   - Jaeger UI: http://localhost:16686
   - API Documentation: http://localhost:8000/docs

## Usage

### Web Interface
1. Open http://localhost:3000
2. Fill in the order form
3. Click "Place Order" to see successful flow
4. Click "Simulate Error Scenario" to see failure tracing
5. View traces in Jaeger UI using the provided links

### Direct API Testing
```bash
# Successful order
curl -X POST http://localhost:8000/orders \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "demo-user",
    "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 2}],
    "payment_method": "credit_card"
  }'

# Error simulation
curl -X POST http://localhost:8000/orders/simulate-error \
  -H "Content-Type: application/json" \
  -d '{
    "user_id": "error-user",
    "items": [{"id": "item-1", "name": "Widget", "price": 29.99, "quantity": 1}],
    "payment_method": "invalid_method"
  }'
```

## Key Features Demonstrated

1. **Request Flow Tracing**: Follow requests across all services
2. **Error Propagation**: See how errors are traced through the system
3. **Asynchronous Operations**: Observe async notification handling
4. **Cross-Service Correlation**: Track requests with correlation IDs
5. **Performance Analysis**: Analyze latency across service boundaries
6. **Sampling Strategies**: See traces being collected and stored

## Observing Traces

1. **Open Jaeger UI**: http://localhost:16686
2. **Select Service**: Choose "api-gateway" from the service dropdown
3. **Find Traces**: Click "Find Traces" to see recent traces
4. **Trace Details**: Click on any trace to see the detailed flow
5. **Span Analysis**: Examine individual spans for timing and errors

## Troubleshooting

- **Services not starting**: Check `docker-compose logs <service-name>`
- **Traces not appearing**: Wait 30 seconds for trace propagation
- **Port conflicts**: Modify ports in docker-compose.yml if needed
- **Memory issues**: Ensure Docker has at least 4GB RAM allocated

## Cleanup

```bash
# Stop all services
docker-compose down

# Remove volumes and images
docker-compose down -v --rmi all
```
