# Chaos Engineering Platform Demo

A complete chaos engineering platform for testing distributed system resilience.

## Quick Start

1. **Build and Start:**
   ```bash
   docker-compose up --build -d
   ```

2. **Access Dashboard:**
   Open http://localhost:8000 in your browser

3. **Run Tests:**
   ```bash
   python test_chaos.py
   ```

## Features

- **Multiple Failure Types:** Latency injection, CPU load, memory pressure, network partitions
- **Real-time Monitoring:** Live system metrics and failure tracking
- **Mock Services:** Simulated microservices for testing
- **Web Interface:** Interactive dashboard for experiment management

## Experiment Types

1. **Latency Injection:** Add network delays to service communications
2. **CPU Load:** Simulate high CPU usage scenarios
3. **Memory Pressure:** Test memory exhaustion handling
4. **Network Partitions:** Simulate network connectivity failures

## Usage Examples

### Create CPU Load Experiment
- Target: user-service
- Type: cpu_load
- Intensity: 0.8 (80% CPU)
- Duration: 30 seconds

### Monitor Results
Watch real-time metrics during experiments to observe:
- System resource impact
- Service degradation patterns
- Recovery behavior

## Architecture

```
Chaos Platform (8000) → Orchestrates experiments
├── User Service (8001)
├── Order Service (8002)
├── Payment Service (8003)
└── Inventory Service (8004)
```

## Testing Commands

```bash
# Test experiment creation
curl -X POST http://localhost:8000/api/experiments \
  -H "Content-Type: application/json" \
  -d '{"name":"Test","target_service":"user-service","failure_type":"latency","intensity":0.5,"duration":20}'

# Check system metrics
curl http://localhost:8000/api/metrics

# View active failures
curl http://localhost:8000/api/failures
```
