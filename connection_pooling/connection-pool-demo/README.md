# Connection Pool Demo - System Design Mastery

A comprehensive demonstration of database connection pooling concepts with real-time monitoring, interactive test scenarios, and performance analysis.

## Features

- **Real-time Monitoring**: Live connection pool metrics and visualization
- **Interactive Scenarios**: Test different load patterns and failure modes
- **Performance Analysis**: Charts and graphs showing pool behavior over time
- **Configuration Management**: Dynamic pool parameter adjustments
- **Educational Interface**: Google Cloud Skills Boost inspired UI

## Quick Start

```bash
# Start the demo
./demo.sh

# Run tests
./demo.sh test

# Run automated scenarios
./demo.sh demo

# View logs
./demo.sh logs

# Clean up
./cleanup.sh
```

## Access Points

- **Web Dashboard**: http://localhost:5000
- **API Health**: http://localhost:5000/api/health
- **Database**: PostgreSQL on localhost:5432 (demo/demo123)

## Test Scenarios

1. **Normal Load** - Typical application usage patterns
2. **High Load** - Stress testing with concurrent requests
3. **Pool Exhaustion** - Trigger and observe pool limits
4. **Connection Leaks** - Simulate resource leak scenarios
5. **Database Slowness** - Test behavior with slow responses

## Learning Objectives

- Understand connection pool sizing trade-offs
- Observe pool exhaustion and recovery patterns
- Learn to monitor pool health metrics
- Experience different failure modes
- Practice pool configuration optimization

## Architecture

- **Frontend**: Interactive dashboard with real-time updates
- **Backend**: Flask application with SQLAlchemy connection pooling
- **Database**: PostgreSQL with sample data
- **Monitoring**: WebSocket-based real-time metrics
- **Containerization**: Docker Compose for easy deployment

## Technologies Used

- Python 3.11
- Flask + SocketIO
- SQLAlchemy + psycopg2
- PostgreSQL 15
- Chart.js for visualizations
- Docker & Docker Compose

## Educational Value

This demo demonstrates production-grade connection pooling patterns used by companies like Netflix, Uber, and Shopify. The scenarios are based on real-world failure patterns and optimization strategies.

## Support

For questions or issues, refer to the System Design Interview Roadmap series or open an issue in the repository.
