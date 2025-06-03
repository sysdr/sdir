# 🐳 Dockerized Vector Clock Distributed System

A production-ready containerized implementation of vector clocks for demonstrating 
causal consistency in distributed systems.

## Quick Start

```bash
./start_demo.sh    # Build and start all containers
./verify_demo.sh   # Verify system functionality  
./stop_demo.sh     # Clean shutdown and cleanup
```

## Architecture

- **3 Vector Clock Processes**: Each in isolated Docker containers
- **Nginx Web Server**: Serves interactive visualization interface
- **Custom Docker Network**: Secure container communication
- **Health Monitoring**: Built-in health checks and auto-restart
- **Production Features**: Graceful shutdown, logging, security

## Container Services

| Service | Container | Ports | Purpose |
|---------|-----------|--------|---------|
| process-0 | vector-clock-process-0 | 8080 | Vector clock process |
| process-1 | vector-clock-process-1 | 8081 | Vector clock process |
| process-2 | vector-clock-process-2 | 8082 | Vector clock process |
| web-interface | vector-clock-web | 8090 | Web visualization |

## Docker Commands

```bash
# View running containers
docker-compose ps

# View logs
docker-compose logs -f [service_name]

# Restart specific service
docker-compose restart process-0

# Scale services (if needed)
docker-compose up -d --scale process-0=2

# Shell into container
docker exec -it vector-clock-process-0 sh

# View resource usage
docker stats
```

## Production Features

- **Health Checks**: Automated container health monitoring
- **Restart Policies**: Automatic restart on failure
- **Resource Limits**: Memory and CPU constraints
- **Security**: Non-root user, minimal attack surface
- **Logging**: Structured logging with timestamps
- **Graceful Shutdown**: SIGTERM handling

## Development vs Production

### Development Mode (default)
- Local port mapping for direct access
- Debug logging enabled
- Hot reload capabilities

### Production Mode
```bash
# Use production compose file
docker-compose -f docker-compose.prod.yml up -d
```

## Monitoring

- **Health Endpoints**: `/health` on each process
- **Status API**: `/status` with detailed metrics
- **Docker Health Checks**: Integrated with Docker daemon
- **Log Aggregation**: Centralized logging via Docker

## Requirements

- Docker Engine 20.0+
- Docker Compose 2.0+
- 2GB available RAM
- Ports 8080-8082, 8090 available

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Port conflicts | `sudo lsof -i :8080-8090` and kill conflicting processes |
| Build failures | `docker-compose build --no-cache` |
| Network issues | `docker network prune && docker-compose up` |
| Memory issues | `docker system prune -a` |

