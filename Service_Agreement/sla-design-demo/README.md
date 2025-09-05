# SLA Design Demo

A comprehensive demonstration of multi-tier Service Level Agreement (SLA) design with real-time monitoring and error budget tracking.

## Features

- **Multi-tier SLA Structure**: Premium (99.99%), Standard (99.9%), Basic (99.0%)
- **Real-time Metrics**: Availability, latency, error budget consumption
- **Service Simulation**: 4 microservices with realistic failure patterns
- **Interactive Testing**: Manual and load testing capabilities
- **Error Budget Tracking**: Real-time budget consumption and burn rate analysis

## Quick Start

```bash
./demo.sh
```

Access the demo at: http://localhost:3000

## Architecture

- **Node.js Application**: Main SLA monitoring system
- **Redis**: Metrics storage and real-time data
- **WebSocket**: Real-time updates to dashboard
- **Service Simulators**: Realistic microservice behavior

## Cleanup

```bash
./cleanup.sh
```

## Learning Objectives

- Understand SLI, SLO, and SLA relationships
- Experience multi-tier service design patterns
- Practice error budget management
- Learn SLA monitoring and alerting strategies
