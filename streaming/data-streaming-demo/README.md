# Data Streaming Architecture Demo

This demo demonstrates real-time data streaming patterns using Apache Kafka, Redis, and Python.

## Architecture

- **Producers**: Generate user events and system metrics
- **Kafka**: Message streaming platform
- **Consumers**: Process events for analytics, recommendations, and notifications
- **Redis**: Store processed data and metrics
- **Web Dashboard**: Real-time visualization

## Quick Start

1. Start the demo:
   ```bash
   ./demo.sh
   ```

2. Open the dashboard:
   ```
   http://localhost:8080
   ```

3. Monitor the streaming pipeline in real-time

## Features

- Real-time event processing
- Lambda architecture pattern
- Fault tolerance and backpressure handling
- Interactive web dashboard
- Comprehensive monitoring

## Testing

Run tests with:
```bash
./test.sh
```

## Cleanup

Clean up resources:
```bash
./cleanup.sh
```
