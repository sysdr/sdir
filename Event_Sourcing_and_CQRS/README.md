# Event Sourcing & CQRS Demo

A comprehensive demonstration of Event Sourcing and CQRS (Command Query Responsibility Segregation) patterns using Node.js, Docker, PostgreSQL, and Redis.

## 🏗️ Architecture

This project demonstrates a microservices architecture implementing Event Sourcing and CQRS:

- **Command Service** (Port 3002): Handles write operations (commands)
- **Event Store** (Port 3001): Immutable append-only log of all events
- **Projection Service** (Port 3004): Builds read models from events
- **Query Service** (Port 3003): Serves optimized read models
- **Dashboard** (Port 3000): Real-time visualization of the system

## 🚀 Quick Start

### Prerequisites

- Docker and Docker Compose
- Bash shell

### Setup

1. **Run the setup script:**
   ```bash
   ./setup.sh
   ```

   This will:
   - Create all necessary directory structures
   - Generate all service code
   - Build Docker containers
   - Start all services
   - Run integration tests

2. **Access the dashboard:**
   Open http://localhost:3000 in your browser

### Manual Setup (Alternative)

If you prefer to set up manually:

```bash
# Build and start services
docker-compose up -d --build

# Wait for services to be ready
sleep 15

# Run tests
./tests/integration.test.sh
```

## 📊 Services

| Service | Port | Description |
|---------|------|-------------|
| Dashboard | 3000 | Web UI for interacting with the system |
| Event Store | 3001 | PostgreSQL-based event store with WebSocket streaming |
| Command Service | 3002 | Handles commands and generates events |
| Query Service | 3003 | Serves read models from Redis |
| Projection Service | 3004 | Processes events and builds projections |

## 🎮 Usage

### Dashboard Features

- **Create Accounts**: Create new bank accounts with initial balances
- **Deposit/Withdraw**: Perform transactions on accounts
- **Real-time Events**: Watch events flow through the system
- **Projection Stats**: Monitor projection processing metrics
- **Replay Projection**: Rebuild read models from scratch

### API Endpoints

#### Command Service (Port 3002)

```bash
# Create account
POST /commands/create-account
Body: { "accountId": "acc-1", "initialBalance": 1000 }

# Deposit
POST /commands/deposit
Body: { "accountId": "acc-1", "amount": 500 }

# Withdraw
POST /commands/withdraw
Body: { "accountId": "acc-1", "amount": 200 }

# Transfer
POST /commands/transfer
Body: { "fromAccountId": "acc-1", "toAccountId": "acc-2", "amount": 100 }

# View command log
GET /commands/log
```

#### Query Service (Port 3003)

```bash
# Get all accounts
GET /accounts

# Get account by ID
GET /accounts/:accountId
```

#### Event Store (Port 3001)

```bash
# Get all events
GET /events/all/stream

# Get events by aggregate
GET /events/:aggregateId

# Get events from sequence
GET /events?fromSequence=0&limit=100
```

#### Projection Service (Port 3004)

```bash
# Get projection stats
GET /stats

# Replay projection
POST /replay
```

## 🧪 Testing

Run the integration test suite:

```bash
./tests/integration.test.sh
```

Or manually test with curl:

```bash
# Create account
curl -X POST http://localhost:3002/commands/create-account \
  -H "Content-Type: application/json" \
  -d '{"accountId":"test-1","initialBalance":1000}'

# Query account (wait a few seconds for projection)
sleep 3
curl http://localhost:3003/accounts/test-1
```

## 🎬 Demo Scripts

### Generate Demo Data

Populate the system with sample data:

```bash
./demo-data.sh
```

### Watch Live Logs

Monitor all services in real-time:

```bash
./demo.sh
```

## 🧹 Cleanup

Stop and remove all containers and volumes:

```bash
./cleanup.sh
```

## 📚 Key Concepts

### Event Sourcing

- All changes are stored as a sequence of events
- Events are immutable and append-only
- State can be rebuilt by replaying events
- Complete audit trail of all changes

### CQRS (Command Query Responsibility Segregation)

- **Commands** (Write): Modify state through events
- **Queries** (Read): Optimized read models for fast queries
- Separation allows independent scaling of read/write operations

### Eventual Consistency

- Read models are updated asynchronously
- There's a brief delay between command execution and query results
- This is a trade-off for scalability and performance

### Projection Replay

- Read models can be rebuilt from scratch
- Useful for:
  - Recovering from errors
  - Adding new read models
  - Migrating data structures

## 🔧 Development

### Project Structure

```
.
├── command-service/     # Command handling service
├── event-store/         # Event store service
├── projection-service/  # Event projection service
├── query-service/       # Query/read model service
├── dashboard/          # React frontend
├── shared/             # Shared utilities
├── tests/              # Integration tests
├── docker-compose.yml  # Docker orchestration
├── setup.sh            # Setup script
├── demo.sh             # Demo script
├── demo-data.sh        # Demo data generator
└── cleanup.sh          # Cleanup script
```

### Adding New Event Types

1. Add event type to `shared/events.js`
2. Add handler in `projection-service/src/server.js`
3. Add command handler in `command-service/src/server.js`
4. Update dashboard UI if needed

### Modifying Projections

Projections are defined in `projection-service/src/server.js`. To add a new projection:

1. Add processing logic in `processEvent()`
2. Store projection data in Redis
3. Add query endpoint in `query-service/src/server.js`

## 🐛 Troubleshooting

### Services not starting

```bash
# Check service status
docker-compose ps

# View logs
docker-compose logs [service-name]

# Restart services
docker-compose restart
```

### Projection not updating

- Check projection service logs: `docker-compose logs projection-service`
- Verify Redis connection
- Check event store is receiving events
- Try replaying projection: `curl -X POST http://localhost:3004/replay`

### Port conflicts

If ports are already in use, modify `docker-compose.yml` to use different ports.

## 📖 Learn More

- [Event Sourcing Pattern](https://martinfowler.com/eaaDev/EventSourcing.html)
- [CQRS Pattern](https://martinfowler.com/bliki/CQRS.html)
- [Event Store Documentation](https://eventstore.org/docs/)

## 📝 License

This is a demonstration project for educational purposes.

