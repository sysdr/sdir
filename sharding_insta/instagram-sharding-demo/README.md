# Instagram Sharding Demo

This demo illustrates Instagram's sharding strategy evolution from monolithic to user-ID based sharding.

## Quick Start

1. **Start Demo**: `./demo.sh`
2. **Access Dashboard**: http://localhost:5000
3. **Clean Up**: `./cleanup.sh`

## Features

- **Interactive Visualization**: See how users distribute across shards
- **Hot Shard Detection**: Simulate and observe hot shard behavior  
- **User Creation**: Add users and watch shard routing in action
- **Load Analysis**: Real-time charts showing shard load distribution

## Learning Objectives

- Understand Instagram's sharding evolution
- Experience user-ID based partitioning
- Observe hot shard patterns
- Learn about cross-shard query challenges

## Architecture

- **Flask**: Web application and API
- **Redis**: Cache and session storage
- **PostgreSQL**: Simulated shard databases
- **Docker**: Containerized deployment

## API Endpoints

- `GET /api/stats` - Overall sharding statistics
- `GET /api/user/{id}` - User data and shard routing
- `GET /api/shard/{id}` - Shard-specific data
- `POST /api/add_user` - Create new user
- `POST /api/simulate_load` - Generate shard load

Happy Learning! 🚀
