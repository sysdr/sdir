# Event Sourcing Banking Demo

A comprehensive demonstration of event sourcing patterns using a banking system example.

## Features

- ✅ Complete event sourcing implementation with SQLite event store
- ✅ Temporal queries - view account state at any point in time
- ✅ Optimistic concurrency control for thread safety
- ✅ Event replay and state reconstruction
- ✅ Interactive web interface for demonstration
- ✅ Comprehensive test suite

## Quick Start

### Option 1: Docker (Recommended)
```bash
docker-compose up --build
```
Access the demo at: http://localhost:8000

### Option 2: Local Development
```bash
pip install -r requirements.txt
python src/main.py
```

## Demo Steps

1. **Create Accounts**: Start by creating one or more bank accounts
2. **Perform Transactions**: Deposit and withdraw money to see events being created
3. **Observe Event Stream**: Watch how each operation creates immutable events
4. **Time Travel Queries**: Use the temporal query feature to see account balances at historical points
5. **View Event History**: Examine the complete event log for any account

## Key Learning Points

- **Immutability**: Events are never modified, only appended
- **State Reconstruction**: Current state is calculated from event history
- **Temporal Queries**: System can answer "what was the state at time X?"
- **Auditability**: Complete history of all changes with full context
- **Replay Capability**: State can be rebuilt from events at any time

## Testing

Run the comprehensive test suite:
```bash
python -m pytest tests/ -v
```

## Architecture

- **Event Store**: SQLite-based append-only event storage
- **Account Aggregate**: Business logic for account operations
- **Event Types**: Strongly typed events for different operations
- **Projection**: Current state views built from events
- **Web Interface**: Interactive demonstration of concepts

This demo illustrates production-ready event sourcing patterns suitable for enterprise applications.
