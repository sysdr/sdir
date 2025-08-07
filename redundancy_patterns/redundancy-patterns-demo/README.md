# Redundancy Patterns Demo

This demo showcases various redundancy patterns in distributed systems:

## Patterns Demonstrated

- **Active-Active**: Multiple services serving traffic simultaneously
- **Active-Passive**: Backup services ready to take over
- **Geographic Distribution**: Services across multiple regions
- **Load Balancing**: Traffic distribution with health checking
- **Automatic Failover**: Services automatically handle failures

## Quick Start

```bash
./demo.sh
```

## Access Points

- **Dashboard**: http://localhost:3000
- **API Status**: http://localhost:3000/api/status
- **Service Health**: http://localhost:300[1-4]/health

## Testing Scenarios

1. **Load Balancing**: Click "Test Load Balancing" to see traffic distribution
2. **Service Failure**: Use "Fail" buttons to simulate service failures
3. **Regional Failure**: Click "Simulate Regional Failure" to test geographic redundancy
4. **Recovery**: Use "Recover" buttons to bring services back online

## Architecture

- Load Balancer (Port 3000): Routes traffic to healthy services
- Service 1 & 2 (Ports 3001-3002): us-east-1 region
- Service 3 (Port 3003): us-west-2 region  
- Service 4 (Port 3004): eu-west-1 region

## Cleanup

```bash
./cleanup.sh
```
