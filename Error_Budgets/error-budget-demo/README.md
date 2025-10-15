# Error Budget Demo

A complete demonstration of error budget monitoring and management.

## Quick Start

```bash
./demo.sh
```

## What You'll See

- **Real-time Error Budget Tracking**: Monitor service reliability metrics
- **Configurable Error Rates**: Adjust failure rates to see budget consumption
- **Budget Status Visualization**: See healthy, critical, and exhausted states
- **SLA Target Comparison**: Understand how performance relates to targets

## Architecture

- **Services**: Simulated microservices with configurable error rates
- **Dashboard**: Real-time web interface showing budget status
- **Calculator**: Error budget calculation engine
- **Traffic Generator**: Realistic request patterns

## Test Scenarios

1. **Normal Operation**: Observe healthy services within budget
2. **Increased Errors**: Raise error rates and watch budget consumption
3. **Budget Exhaustion**: See what happens when budgets are exceeded
4. **Recovery**: Watch budgets recover as error rates decrease

## Commands

- `./demo.sh` - Start the complete demo
- `./demo.sh test` - Run tests only
- `./demo.sh stop` - Stop services
- `./cleanup.sh` - Complete cleanup

## Access Points

- Dashboard: http://localhost:3000
- API: http://localhost:3000/api/error-budgets
