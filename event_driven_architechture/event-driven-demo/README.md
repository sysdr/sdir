# Event-Driven Architecture Demo

This demo showcases event-driven architecture patterns and anti-patterns with a real microservices system.

## Features

- **Event Sourcing** with Order Service
- **CQRS** with Inventory Service
- **Pub/Sub** messaging patterns
- **Real-time Dashboard** with WebSocket updates
- **Anti-pattern demonstrations** (Event Storms)

## Quick Start

```bash
./demo.sh
```

Access the dashboard at http://localhost:3000

## Architecture

- **Order Service** (Port 3001): Event sourcing with PostgreSQL event store
- **Inventory Service** (Port 3002): CQRS with separate read/write models
- **Payment Service** (Port 3003): Pub/Sub event publishing
- **Notification Service** (Port 3004): Event consumer
- **Analytics Service** (Port 3005): Event aggregation
- **Anti-pattern Service** (Port 3006): Demonstrates event storms

## Clean Up

```bash
./cleanup.sh
```
