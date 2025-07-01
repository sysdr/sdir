# Scaling to 1M Users - Interactive Demo

This demo simulates the journey of scaling a web application from 1 user to 1 million users, showing the architectural decisions and trade-offs at each stage.

## Architecture Stages

1. **Single Server (1-1K users)**: Everything on one machine
2. **Separate Database (1K-10K users)**: Database isolation
3. **Load Balanced (10K-100K users)**: Horizontal scaling
4. **Caching & CDN (100K-500K users)**: Performance optimization
5. **Microservices (500K+ users)**: Service decomposition

## Features

- Real-time metrics simulation
- Interactive load testing
- Architecture visualization
- Performance impact demonstration
- Scaling decision triggers

## API Endpoints

- `GET /api/metrics` - Current system metrics
- `GET /api/architecture` - Architecture information
- `POST /api/load-test/start` - Start load test
- `POST /api/traffic-spike` - Trigger traffic spike
- `POST /api/scale-up` - Scale to next stage
- `POST /api/reset` - Reset demo

## Learning Objectives

- Understand scaling triggers and decisions
- Experience performance degradation patterns
- Learn about capacity planning
- See the evolution of system architecture
- Understand trade-offs at each stage
