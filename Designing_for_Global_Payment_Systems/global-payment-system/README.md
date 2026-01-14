# Global Payment System Demo

A production-grade demonstration of multi-region payment processing with real-time currency conversion, fraud detection, and strong consistency guarantees.

## Features

- **Multi-Region Processing**: Geographic distribution for low latency
- **Currency Conversion**: Real-time exchange rates with locked pricing
- **Idempotency**: Duplicate payment prevention with 24h TTL
- **Fraud Detection**: ML-based risk scoring
- **State Machine**: Transactional payment lifecycle management
- **Real-Time Dashboard**: Live metrics and payment visualization

## Quick Start

```bash
bash setup.sh
```

## Architecture

- **Gateway Service**: Regional entry points (port 3000)
- **Processor Service**: Payment orchestration (port 3001)
- **PostgreSQL**: Transactional storage
- **Redis**: Idempotency cache and pub/sub
- **React Dashboard**: Real-time monitoring (port 3002)

## Run Demo

```bash
cd global-payment-system
bash demo.sh
```

Then open http://localhost:3002

## Run Tests

```bash
docker exec -it global-payment-system-gateway-1 sh -c "cd /tests && npm install && node test.js"
```

## Cleanup

```bash
cd global-payment-system
bash cleanup.sh
```

## Experiments

1. **Test Idempotency**: Submit duplicate payments with same idempotency key
2. **Currency Arbitrage**: Rapid payments with volatile pairs
3. **Fraud Detection**: High-value transactions trigger rejection
4. **State Tracking**: Monitor payment lifecycle transitions

## Production Patterns

- Event sourcing for financial ledger
- Two-phase commit for multi-leg transfers
- Circuit breakers for cascading failure prevention
- Hybrid logical clocks for distributed ordering
