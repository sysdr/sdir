# Black Friday: Extreme Load Preparation Demo

This demo simulates a complete e-commerce system designed to handle Black Friday traffic spikes with intelligent load management, circuit breakers, and auto-scaling.

## Quick Start

```bash
./demo.sh
```

## What You'll Experience

### 🎯 Black Friday Traffic Simulation
- **300x Traffic Spike**: Simulate going from 100 RPS to 30,000+ RPS instantly
- **Real User Patterns**: Realistic traffic patterns with different user priorities
- **System Response**: Watch how the system adapts and protects itself

### 🔧 Intelligent Protection Mechanisms
- **Multi-Level Circuit Breakers**: 5-state circuit breaker (Closed → Warning → Half-Open → Open → Emergency)
- **Smart Load Shedding**: Priority-based request handling (VIP → Regular → Anonymous)
- **Auto-Scaling Events**: Automatic capacity adjustments based on load

### 📊 Real-Time Monitoring
- **Live Dashboard**: Real-time metrics with beautiful visualizations
- **Performance Tracking**: RPS, response times, error rates, and scaling events
- **System Health**: Circuit breaker states and load shedding decisions

## Architecture Components

- **Frontend**: React dashboard with real-time Socket.IO updates
- **Backend**: Node.js API with circuit breakers and load balancing
- **Load Generator**: Intelligent traffic simulation with realistic patterns
- **Monitoring**: Prometheus metrics and Grafana dashboards
- **Caching**: Redis for fast operations and circuit breaker state

## Access Points

| Component | URL | Purpose |
|-----------|-----|---------|
| Main Dashboard | http://localhost:3000 | Real-time monitoring and controls |
| API Server | http://localhost:3001 | REST API with circuit protection |
| Prometheus | http://localhost:9090 | Raw metrics and queries |
| Grafana | http://localhost:3002 | Advanced dashboards (admin/admin) |

## Demo Scenarios

### Scenario 1: Normal Operations
- Observe baseline metrics (< 100 RPS)
- Circuit breaker in CLOSED state
- Normal response times

### Scenario 2: Black Friday Load Test
- Click "Start Black Friday Load Test" in dashboard
- Watch traffic spike to 3000+ RPS
- Observe circuit breaker transitions
- See load shedding activation

### Scenario 3: System Recovery
- Watch system stabilize after load test
- Circuit breaker returns to CLOSED
- Scaling events show capacity adjustments

## Key Learning Points

1. **Predictive Scaling**: How systems prepare for expected load spikes
2. **Circuit Breaker States**: Multi-level protection beyond simple on/off
3. **Load Shedding Strategy**: Intelligent request prioritization
4. **Real-Time Monitoring**: Critical metrics for load management
5. **Graceful Degradation**: Maintaining core functionality under extreme load

## Cleanup

```bash
./cleanup.sh
```

This removes all containers, images, and volumes created by the demo.

## Technical Implementation

- **Circuit Breaker**: Opossum.js with custom state machine
- **Load Testing**: Autocannon with realistic traffic patterns
- **Metrics**: Prometheus with custom business metrics
- **Real-Time Updates**: Socket.IO for live dashboard updates
- **Containerization**: Docker Compose with optimized images

## Production Insights

This demo demonstrates patterns used by:
- **Amazon** during Prime Day traffic spikes
- **Target** for Black Friday preparation
- **Shopify** for flash sale protection
- **Netflix** for content launch events

The techniques shown here scale from small startups to hyperscale platforms handling millions of requests per second.
